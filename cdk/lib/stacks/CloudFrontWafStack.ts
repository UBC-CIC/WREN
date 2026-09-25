import { Stack, type StackProps, CfnOutput, Duration, RemovalPolicy } from "aws-cdk-lib";
import * as cloudfront from "aws-cdk-lib/aws-cloudfront";
import * as cloudwatch from "aws-cdk-lib/aws-cloudwatch";
import * as cloudwatchActions from "aws-cdk-lib/aws-cloudwatch-actions";
import * as origins from "aws-cdk-lib/aws-cloudfront-origins";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as sns from "aws-cdk-lib/aws-sns";
import * as subscriptions from "aws-cdk-lib/aws-sns-subscriptions";
import * as wafv2 from "aws-cdk-lib/aws-wafv2";
import type { Construct } from "constructs";

import type { AppConfig } from "../config";

/**
 * Props for the CloudFrontWaf stack. Receives the API Gateway endpoint and
 * (optionally) the Amplify app domain to set up as origins.
 */
export interface CloudFrontWafStackProps extends StackProps {
  readonly config: AppConfig;
  /** The API Gateway regional endpoint URL (without trailing slash). */
  readonly apiEndpoint: string;
  /** The Amplify app default domain (e.g. `main.d1234abc.amplifyapp.com`). */
  readonly amplifyDomain?: string;
}

/**
 * `${StackPrefix}-CloudFrontWaf` — CloudFront distribution + WAF.
 *
 * - WAF WebACL with AWS Managed Rule Sets (Common, Known Bad Inputs, IP
 *   Reputation) + a rate-based rule (2000 req/5 min per IP).
 * - CloudFront distribution fronting the API Gateway regional endpoint as
 *   the default origin (and optionally Amplify for the frontend).
 * - HTTPS only (ViewerProtocolPolicy.REDIRECT_TO_HTTPS).
 * - Standard security headers via a response headers policy.
 *
 * Requirements: REQ-NFR-SCALE-01 (edge caching / rate limiting for graceful
 * degradation), REQ-SEC-ROLE-01 (defense-in-depth via WAF).
 */
export class CloudFrontWafStack extends Stack {
  public readonly distribution: cloudfront.Distribution;
  public readonly webAcl: wafv2.CfnWebACL;

  constructor(scope: Construct, id: string, props: CloudFrontWafStackProps) {
    super(scope, id, props);

    const { config } = props;

    // -------------------------------------------------------------------
    // WAF WebACL (must be in us-east-1 for CloudFront; deploy this stack
    // in us-east-1 OR use a CloudFormation custom resource. Here we define
    // the ACL and associate it at distribution creation via webAclId.)
    // -------------------------------------------------------------------
    this.webAcl = new wafv2.CfnWebACL(this, "WebAcl", {
      name: `${config.stackPrefix}-web-acl`,
      scope: "CLOUDFRONT",
      defaultAction: { allow: {} },
      visibilityConfig: {
        cloudWatchMetricsEnabled: true,
        metricName: `${config.stackPrefix}-waf-metric`,
        sampledRequestsEnabled: true,
      },
      rules: [
        // AWS Managed - Common Rule Set
        {
          name: "AWSManagedRulesCommonRuleSet",
          priority: 1,
          overrideAction: { none: {} },
          statement: {
            managedRuleGroupStatement: {
              vendorName: "AWS",
              name: "AWSManagedRulesCommonRuleSet",
            },
          },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: `${config.stackPrefix}-common-rules`,
            sampledRequestsEnabled: true,
          },
        },
        // AWS Managed - Known Bad Inputs
        {
          name: "AWSManagedRulesKnownBadInputsRuleSet",
          priority: 2,
          overrideAction: { none: {} },
          statement: {
            managedRuleGroupStatement: {
              vendorName: "AWS",
              name: "AWSManagedRulesKnownBadInputsRuleSet",
            },
          },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: `${config.stackPrefix}-bad-inputs`,
            sampledRequestsEnabled: true,
          },
        },
        // AWS Managed - IP Reputation List
        {
          name: "AWSManagedRulesAmazonIpReputationList",
          priority: 3,
          overrideAction: { none: {} },
          statement: {
            managedRuleGroupStatement: {
              vendorName: "AWS",
              name: "AWSManagedRulesAmazonIpReputationList",
            },
          },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: `${config.stackPrefix}-ip-reputation`,
            sampledRequestsEnabled: true,
          },
        },
        // Rate-based rule: 2000 requests per 5-minute window per IP
        {
          name: "RateLimitPerIP",
          priority: 4,
          action: { block: {} },
          statement: {
            rateBasedStatement: {
              limit: 2000,
              aggregateKeyType: "IP",
            },
          },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: `${config.stackPrefix}-rate-limit`,
            sampledRequestsEnabled: true,
          },
        },
      ],
    });

    // -------------------------------------------------------------------
    // CloudFront Distribution
    // -------------------------------------------------------------------
    // Parse the API endpoint to extract the domain (strip https:// and path).
    const apiDomain = props.apiEndpoint
      .replace(/^https?:\/\//, "")
      .replace(/\/.*$/, "");

    const apiOrigin = new origins.HttpOrigin(apiDomain, {
      protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
    });

    const securityHeadersPolicy = new cloudfront.ResponseHeadersPolicy(
      this,
      "SecurityHeaders",
      {
        comment: `${config.stackPrefix} security headers (CSP blocks javascript: URIs)`,
        securityHeadersBehavior: {
          contentSecurityPolicy: {
            contentSecurityPolicy:
              "default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' https: wss:",
            override: true,
          },
          contentTypeOptions: { override: true },
          frameOptions: {
            frameOption: cloudfront.HeadersFrameOption.DENY,
            override: true,
          },
          referrerPolicy: {
            referrerPolicy:
              cloudfront.HeadersReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN,
            override: true,
          },
          strictTransportSecurity: {
            accessControlMaxAge: Duration.seconds(31_536_000),
            includeSubdomains: true,
            override: true,
          },
          xssProtection: { protection: true, modeBlock: true, override: true },
        },
      },
    );

    const accessLogs = new s3.Bucket(this, "AccessLogs", {
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      objectOwnership: s3.ObjectOwnership.OBJECT_WRITER,
      lifecycleRules: [
        {
          id: "ExpireCloudFrontAccessLogs",
          expiration: Duration.days(30),
          abortIncompleteMultipartUploadAfter: Duration.days(7),
        },
      ],
      removalPolicy: RemovalPolicy.RETAIN,
    });

    this.distribution = new cloudfront.Distribution(this, "Distribution", {
      comment: `${config.stackPrefix} - WREN Writing Coach CDN`,
      defaultBehavior: {
        origin: apiOrigin,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED, // API — no caching
        originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER_EXCEPT_HOST_HEADER,
        responseHeadersPolicy: securityHeadersPolicy,
      },
      webAclId: this.webAcl.attrArn,
      httpVersion: cloudfront.HttpVersion.HTTP2_AND_3,
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100, // NA + Europe
      enableLogging: true,
      logBucket: accessLogs,
      logFilePrefix: "cloudfront/",
      publishAdditionalMetrics: true,
    });

    // If Amplify domain is provided, add it as a secondary behavior for the
    // frontend SPA (path pattern: /app/*).
    if (props.amplifyDomain) {
      const amplifyOrigin = new origins.HttpOrigin(props.amplifyDomain, {
        protocolPolicy: cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
      });
      this.distribution.addBehavior("/app/*", amplifyOrigin, {
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        responseHeadersPolicy: securityHeadersPolicy,
      });
    }

    // CloudFront metrics are us-east-1 / Region=Global — keep alarms in this
    // stack rather than importing the ca-central-1 Observability SNS topic.
    const alarmTopic = new sns.Topic(this, "AlarmTopic", {
      topicName: `${config.stackPrefix}-cloudfront-alarms`,
      displayName: `${config.stackPrefix} CloudFront Alarms`,
    });
    if (config.alarmEmail !== undefined) {
      alarmTopic.addSubscription(new subscriptions.EmailSubscription(config.alarmEmail));
    }

    const cfDimensions = {
      DistributionId: this.distribution.distributionId,
      Region: "Global",
    };
    const fiveXx = new cloudwatch.Alarm(this, "FiveXxAlarm", {
      alarmName: `${config.stackPrefix}-cloudfront-5xx`,
      metric: new cloudwatch.Metric({
        namespace: "AWS/CloudFront",
        metricName: "5xxErrorRate",
        dimensionsMap: cfDimensions,
        statistic: "Average",
        period: Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: "CloudFront 5xx error rate > 5% for 10 minutes",
    });
    fiveXx.addAlarmAction(new cloudwatchActions.SnsAction(alarmTopic));

    const fourXx = new cloudwatch.Alarm(this, "FourXxAlarm", {
      alarmName: `${config.stackPrefix}-cloudfront-4xx`,
      metric: new cloudwatch.Metric({
        namespace: "AWS/CloudFront",
        metricName: "4xxErrorRate",
        dimensionsMap: cfDimensions,
        statistic: "Average",
        period: Duration.minutes(5),
      }),
      threshold: 50,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: "CloudFront 4xx error rate > 50% for 15 minutes",
    });
    fourXx.addAlarmAction(new cloudwatchActions.SnsAction(alarmTopic));

    // -------------------------------------------------------------------
    // Outputs
    // -------------------------------------------------------------------
    new CfnOutput(this, "DistributionId", {
      value: this.distribution.distributionId,
      description: "CloudFront distribution ID",
    });
    new CfnOutput(this, "DistributionDomainName", {
      value: this.distribution.distributionDomainName,
      description: "CloudFront distribution domain name",
    });
    new CfnOutput(this, "WebAclArn", {
      value: this.webAcl.attrArn,
      description: "WAF WebACL ARN",
    });
  }
}
