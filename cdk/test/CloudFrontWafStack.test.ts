import { App } from "aws-cdk-lib";
import { Match, Template } from "aws-cdk-lib/assertions";

import { CloudFrontWafStack } from "../lib/stacks/CloudFrontWafStack.js";
import { testConfig } from "./helpers.js";

function synthCloudFront() {
  const config = testConfig();
  const stack = new CloudFrontWafStack(new App(), `${config.stackPrefix}-CloudFrontWaf`, {
    env: { account: config.env.account, region: "us-east-1" },
    config,
    apiEndpoint: "https://abc123.execute-api.ca-central-1.amazonaws.com/prod/",
  });
  return { config, template: Template.fromStack(stack) };
}

describe("CloudFrontWafStack observability", () => {
  it("enables distribution access logging to an S3 bucket that expires objects after 30 days", () => {
    const { template } = synthCloudFront();

    template.hasResourceProperties("AWS::S3::Bucket", {
      LifecycleConfiguration: {
        Rules: Match.arrayWith([
          Match.objectLike({
            Status: "Enabled",
            ExpirationInDays: 30,
          }),
        ]),
      },
    });

    const buckets = Object.keys(template.findResources("AWS::S3::Bucket"));
    expect(buckets.length).toBeGreaterThan(0);
    const logging = template.findResources("AWS::CloudFront::Distribution");
    const dist = Object.values(logging)[0];
    expect(dist?.Properties?.DistributionConfig?.Logging).toEqual(
      expect.objectContaining({
        Prefix: "cloudfront/",
      }),
    );
  });

  it("publishes additional CloudFront metrics", () => {
    const { template } = synthCloudFront();
    template.hasResourceProperties("AWS::CloudFront::MonitoringSubscription", {
      MonitoringSubscription: {
        RealtimeMetricsSubscriptionConfig: Match.objectLike({
          RealtimeMetricsSubscriptionStatus: "Enabled",
        }),
      },
    });
  });

  it("alarms on elevated 5xx and 4xx error rates", () => {
    const { config, template } = synthCloudFront();
    template.hasResourceProperties("AWS::CloudWatch::Alarm", {
      AlarmName: `${config.stackPrefix}-cloudfront-5xx`,
      Namespace: "AWS/CloudFront",
      MetricName: "5xxErrorRate",
      Threshold: 5,
    });
    template.hasResourceProperties("AWS::CloudWatch::Alarm", {
      AlarmName: `${config.stackPrefix}-cloudfront-4xx`,
      Namespace: "AWS/CloudFront",
      MetricName: "4xxErrorRate",
      Threshold: 50,
    });
  });
});
