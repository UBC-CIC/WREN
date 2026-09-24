import * as path from "path";
import { Stack, type StackProps, Duration, CfnOutput, RemovalPolicy } from "aws-cdk-lib";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as lambdaNodejs from "aws-cdk-lib/aws-lambda-nodejs";
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as iam from "aws-cdk-lib/aws-iam";
import * as sqs from "aws-cdk-lib/aws-sqs";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as events from "aws-cdk-lib/aws-events";
import * as targets from "aws-cdk-lib/aws-events-targets";
import * as lambdaEventSources from "aws-cdk-lib/aws-lambda-event-sources";
import * as secretsmanager from "aws-cdk-lib/aws-secretsmanager";
import type { IKey } from "aws-cdk-lib/aws-kms";
import type { Construct } from "constructs";

import { AppSyncRealtimeConstruct } from "../constructs/AppSyncRealtimeConstruct";
import { NotificationInfraConstruct } from "../constructs/NotificationInfraConstruct";

import type { AppDbRole } from "../appDbRoles.js";
import { bedrockModelIdParameterName, cacheEnabledWorkloadsEnv, type AppConfig } from "../config";
import { corsLambdaEnvironment } from "../corsOrigins";

/** IAM resources for us.anthropic.* / us.meta.* cross-region inference profiles. */
function crisBedrockInvokeResources(region: string, account: string): string[] {
  const profileRegions = [...new Set([region, "us-east-1", "us-east-2", "us-west-2"])];
  const resources: string[] = [];
  for (const r of profileRegions) {
    resources.push(`arn:aws:bedrock:${r}:${account}:inference-profile/us.anthropic.*`);
    resources.push(`arn:aws:bedrock:${r}:${account}:inference-profile/us.meta.*`);
  }
  // Include the caller region: InvokeModel on us.* profiles from ca-central-1
  // still authorizes arn:aws:bedrock:<region>::foundation-model/anthropic.*.
  const fmRegions = [...new Set([region, "us-east-1", "us-east-2", "us-west-2"])];
  for (const r of fmRegions) {
    resources.push(`arn:aws:bedrock:${r}::foundation-model/anthropic.*`);
    resources.push(`arn:aws:bedrock:${r}::foundation-model/meta.*`);
  }
  return resources;
}

/**
 * Props for the Compute stack. Receives concrete VPC and resource identifiers
 * from foundational stacks (per CDK steering: constructs receive concrete
 * objects, stacks resolve from SSM/lookup).
 */
export interface ComputeStackProps extends StackProps {
  readonly config: AppConfig;
  readonly vpc: ec2.IVpc;
  /** Existing Feedback Engine ECR repository owned or explicitly imported by Cicd. */
  readonly feedbackEngineRepository: ecr.IRepository;
  /** RDS Proxy endpoint hostname (from Database stack via SSM). */
  readonly databaseProxyEndpoint: string;
  /** Per-Lambda Secrets Manager ARNs (Postgres role secrets, not dbadmin). */
  readonly databaseSecretArns: Record<AppDbRole, string>;
  /** S3 bucket name for submitted documents. */
  readonly documentsBucketName: string;
  /** S3 bucket name for reference materials. */
  readonly referenceBucketName: string;
  /** KMS key encrypting the documents / reference buckets (SSE-KMS). */
  readonly storageEncryptionKey: IKey;
  /** DynamoDB conversation table name. */
  readonly conversationTableName: string;
  /** Cognito User Pool ID (from Cognito stack). */
  readonly userPoolId: string;
  /** Cognito User Pool Client ID (from Cognito stack). */
  readonly userPoolClientId: string;
  /** Bedrock Guardrail ID for admin prompt injection detection. */
  readonly promptGuardrailId: string;
}

/**
 * `${StackPrefix}-Compute` — All service Lambda functions.
 *
 * Maps the design's subsystem→compute assignments:
 *   - Document/Draft Lambda (Node 22): ingestion, extraction, draft versioning
 *   - Authorizer Lambda (Node 22): Cognito JWT verification + app-DB mapping
 *   - Admin/Config/Auth/Usage Lambda (Node 22): transactional Postgres writes
 *   - Audit Lambda (Node 22): activity log + aggregate analytics
 *   - Feedback Orchestrator Lambda (Node 22): enqueues feedback jobs to SQS
 *   - Feedback Engine Lambda (Python 3.12, container): AI workload via Bedrock
 *   - Diff/Anchor/Progress Lambda (Python 3.12): pure-logic diff/resolution
 *
 * Each function has its own scoped IAM role (least-privilege). The Feedback
 * Engine is fronted by an SQS queue + DLQ for async execution with graceful
 * degradation under overload (REQ-NFR-SCALE-01 criterion 3).
 *
 * Requirements: 47.1 (scale compute), 47.2 (auto-scale), 47.3 (queue/throttle)
 */
export class ComputeStack extends Stack {
  public readonly authorizerFunction: lambda.Function;
  public readonly documentFunction: lambda.Function;
  public readonly adminFunction: lambda.Function;
  public readonly auditFunction: lambda.Function;
  public readonly feedbackOrchestratorFunction: lambda.Function;
  public readonly feedbackEngineFunction: lambda.Function;
  public readonly diffAnchorProgressFunction: lambda.Function;
  public readonly feedbackQueue: sqs.Queue;
  public readonly feedbackDlq: sqs.Queue;
  public readonly documentIngestQueue: sqs.Queue;
  public readonly documentIngestDlq: sqs.Queue;
  public readonly notificationFunction: lambda.Function;
  public readonly notificationDlq: sqs.Queue;
  public readonly notificationTopicArn: string;
  public readonly appSyncGraphqlUrl: string;
  public readonly appSyncAuthorizerFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: ComputeStackProps) {
    super(scope, id, props);

    const { config, vpc } = props;

    // Select private subnets for data-plane Lambdas (security steering).
    const privateSubnets = vpc.selectSubnets({
      subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
    });

    // Shared environment variables for Node Lambdas that access the DB.
    // Per-role secrets are username+password only; host/port/dbname are
    // non-secret overrides (the RDS admin secret used to embed them).
    const dbEnv = (secretArn: string) => ({
      DB_PROXY_HOST: props.databaseProxyEndpoint,
      DB_PORT: "5432",
      DB_NAME: "appdb",
      DB_SECRET_ARN: secretArn,
      NODE_OPTIONS: "--enable-source-maps",
    });
    const secrets = props.databaseSecretArns;
    const corsEnv = corsLambdaEnvironment(config);

    // Shared bundling config: workspace packages are resolved from the monorepo
    // root node_modules (npm workspaces hoist them there). esbuild runs from the
    // monorepo root so it naturally resolves @wren/* via the workspace symlinks.
    const monorepoRoot = path.join(__dirname, "../../..");
    const sharedBundling: lambdaNodejs.BundlingOptions = {
      minify: true,
      sourceMap: true,
      target: "node22",
    };
    // pdf.js / pdf-parse must ship as real node_modules (workers + ESM), not
    // an esbuild bundle — otherwise Lambda cannot load the digital PDF path.
    const documentBundling: lambdaNodejs.BundlingOptions = {
      ...sharedBundling,
      nodeModules: ["pdfjs-dist", "pdf-parse"],
    };

    // One-way salt for activity-log actor pseudonyms. Generated into Secrets
    // Manager (never a guessable path). The Lambda receives ONLY the secret
    // id/arn as non-secret config — never the salt value itself, which would
    // otherwise be recoverable via lambda:GetFunctionConfiguration.
    // activityLogService fetches the value from Secrets Manager at runtime
    // (outside the handler, cached per container) from
    // WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN.
    const activityPseudonymSaltName = `${config.stackPrefix}/audit/pseudonym-salt`;
    const activityPseudonymSalt = config.auditPseudonymSaltOwnership === "external"
      ? secretsmanager.Secret.fromSecretNameV2(
        this,
        "ActivityPseudonymSalt",
        activityPseudonymSaltName,
      )
      : new secretsmanager.Secret(this, "ActivityPseudonymSalt", {
        secretName: activityPseudonymSaltName,
        description: "One-way salt for activity-log actor pseudonyms",
        generateSecretString: {
          passwordLength: 48,
          excludePunctuation: true,
        },
      });
    if (config.auditPseudonymSaltOwnership === "managed") {
      activityPseudonymSalt.applyRemovalPolicy(RemovalPolicy.RETAIN);
    }
    const activitySaltEnv = {
      WREN_ACTIVITY_PSEUDONYM_SALT_SECRET_ARN: activityPseudonymSalt.secretArn,
    };

    // -----------------------------------------------------------------------
    // Lambda Authorizer (Node 22)
    // -----------------------------------------------------------------------
    this.authorizerFunction = new lambdaNodejs.NodejsFunction(this, "AuthorizerFn", {
      functionName: `${config.stackPrefix}-authorizer`,
      entry: path.join(monorepoRoot, "backend/auth/src/authorizer.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_22_X,
      memorySize: 256,
      // VPC cold start (ENI + Secrets Manager + RDS Proxy + JWKS) can exceed 10s.
      timeout: Duration.seconds(20),
      // Guaranteed concurrency FLOOR on the auth critical path. Prevents the
      // shared account pool from being starved by long-running functions
      // (authorizer throttling remediation — see lambdaConcurrency.ts).
      reservedConcurrentExecutions: config.lambdaConcurrency.authorizer,
      vpc,
      vpcSubnets: privateSubnets,
      projectRoot: monorepoRoot,
      depsLockFilePath: path.join(monorepoRoot, "package-lock.json"),
      environment: {
        ...dbEnv(secrets.wren_authorizer),
        COGNITO_USER_POOL_ID: props.userPoolId,
        COGNITO_CLIENT_ID: props.userPoolClientId,
        ...(config.technicalAdminBootstrapSubject
          ? { TECHNICAL_ADMIN_BOOTSTRAP_SUBJECT: config.technicalAdminBootstrapSubject }
          : {}),
      },
      bundling: sharedBundling,
    });

    // -----------------------------------------------------------------------
    // Document / Draft Service Lambda (Node 22)
    // -----------------------------------------------------------------------
    this.documentFunction = new lambdaNodejs.NodejsFunction(this, "DocumentFn", {
      functionName: `${config.stackPrefix}-document`,
      entry: path.join(monorepoRoot, "backend/document/src/lambda-handler.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_22_X,
      // Textract OCR needs headroom for multi-page PDF analysis.
      // PDF ingest is async via SQS so API Gateway's ~29s sync cap does not
      // abort large OCR jobs — the worker uses this full timeout.
      memorySize: 2048,
      timeout: Duration.minutes(3),
      // Reserved CAP so a burst of long-running OCR jobs cannot consume the
      // whole account pool and starve the authorizer. Aligns with the ingest
      // SQS maxConcurrency below (authorizer throttling remediation).
      reservedConcurrentExecutions: config.lambdaConcurrency.document,
      vpc,
      vpcSubnets: privateSubnets,
      projectRoot: monorepoRoot,
      depsLockFilePath: path.join(monorepoRoot, "package-lock.json"),
      environment: {
        ...dbEnv(secrets.wren_document),
        ...corsEnv,
        DOCUMENTS_BUCKET_NAME: props.documentsBucketName,
        DOCUMENTS_KMS_KEY_ARN: props.storageEncryptionKey.keyArn,
        PDF_OCR_ENABLED: "true",
        // Textract is the OCR fallback when a PDF has no usable text layer.
        PDF_OCR_ENGINE: "textract",
        CONVERSATION_TABLE_NAME: props.conversationTableName,
      },
      bundling: documentBundling,
    });

    // -----------------------------------------------------------------------
    // Document ingest queue (async PDF OCR via Textract)
    // -----------------------------------------------------------------------
    this.documentIngestDlq = new sqs.Queue(this, "DocumentIngestDlq", {
      queueName: `${config.stackPrefix}-document-ingest-dlq`,
      retentionPeriod: Duration.days(14),
    });

    this.documentIngestQueue = new sqs.Queue(this, "DocumentIngestQueue", {
      queueName: `${config.stackPrefix}-document-ingest-queue`,
      // Must exceed DocumentFn timeout so in-flight OCR is not redelivered early.
      visibilityTimeout: Duration.minutes(4),
      deadLetterQueue: {
        queue: this.documentIngestDlq,
        maxReceiveCount: 3,
      },
    });

    this.documentFunction.addEnvironment(
      "DOCUMENT_INGEST_QUEUE_URL",
      this.documentIngestQueue.queueUrl,
    );
    this.documentIngestQueue.grantSendMessages(this.documentFunction);
    this.documentFunction.addEventSource(
      new lambdaEventSources.SqsEventSource(this.documentIngestQueue, {
        batchSize: 1,
        maxConcurrency: 5,
      }),
    );

    // -----------------------------------------------------------------------
    // Admin / Config / Auth / Usage Service Lambda (Node 22)
    // -----------------------------------------------------------------------
    this.adminFunction = new lambdaNodejs.NodejsFunction(this, "AdminFn", {
      functionName: `${config.stackPrefix}-admin`,
      entry: path.join(monorepoRoot, "backend/admin/src/lambda-handler.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_22_X,
      memorySize: 512,
      timeout: Duration.seconds(30),
      vpc,
      vpcSubnets: privateSubnets,
      projectRoot: monorepoRoot,
      depsLockFilePath: path.join(monorepoRoot, "package-lock.json"),
      environment: {
        ...dbEnv(secrets.wren_admin),
        ...corsEnv,
        ...activitySaltEnv,
        REFERENCE_BUCKET_NAME: props.referenceBucketName,
        BEDROCK_MODEL_ID: config.bedrockModelId,
        COGNITO_USER_POOL_ID: props.userPoolId,
        PROMPT_GUARDRAIL_ID: props.promptGuardrailId,
        PROMPT_GUARDRAIL_VERSION: "DRAFT",
        STACK_PREFIX: config.stackPrefix,
      },
      bundling: sharedBundling,
    });

    // -----------------------------------------------------------------------
    // Audit / Activity-Log / Analytics Service Lambda (Node 22)
    // -----------------------------------------------------------------------
    this.auditFunction = new lambdaNodejs.NodejsFunction(this, "AuditFn", {
      functionName: `${config.stackPrefix}-audit`,
      entry: path.join(monorepoRoot, "backend/admin/src/lambda-audit.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_22_X,
      memorySize: 256,
      timeout: Duration.seconds(15),
      vpc,
      vpcSubnets: privateSubnets,
      projectRoot: monorepoRoot,
      depsLockFilePath: path.join(monorepoRoot, "package-lock.json"),
      environment: {
        ...dbEnv(secrets.wren_audit),
        ...corsEnv,
        ...activitySaltEnv,
      },
      bundling: sharedBundling,
    });

    // -----------------------------------------------------------------------
    // Feedback DLQ + Queue (SQS — async job execution, REQ-NFR-SCALE-01)
    // -----------------------------------------------------------------------
    this.feedbackDlq = new sqs.Queue(this, "FeedbackDlq", {
      queueName: `${config.stackPrefix}-feedback-dlq`,
      retentionPeriod: Duration.days(14),
    });

    this.feedbackQueue = new sqs.Queue(this, "FeedbackQueue", {
      queueName: `${config.stackPrefix}-feedback-queue`,
      visibilityTimeout: Duration.minutes(16), // Must exceed engine timeout
      deadLetterQueue: {
        queue: this.feedbackDlq,
        maxReceiveCount: 3, // Retry up to 3 times before DLQ
      },
    });

    // -----------------------------------------------------------------------
    // Feedback Orchestrator Lambda (Node 22) — enqueues to SQS, returns job id
    // -----------------------------------------------------------------------
    this.feedbackOrchestratorFunction = new lambdaNodejs.NodejsFunction(this, "FeedbackOrchestratorFn", {
      functionName: `${config.stackPrefix}-feedback-orchestrator`,
      entry: path.join(monorepoRoot, "backend/feedback/src/lambda-handler.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_22_X,
      memorySize: 512,
      // Ask WREN invokes Bedrock synchronously on this Lambda.
      timeout: Duration.seconds(60),
      vpc,
      vpcSubnets: privateSubnets,
      projectRoot: monorepoRoot,
      depsLockFilePath: path.join(monorepoRoot, "package-lock.json"),
      environment: {
        ...dbEnv(secrets.wren_feedback_orch),
        ...corsEnv,
        FEEDBACK_QUEUE_URL: this.feedbackQueue.queueUrl,
        CONVERSATION_TABLE_NAME: props.conversationTableName,
        BEDROCK_MODEL_ID: config.bedrockModelId,
        STACK_PREFIX: config.stackPrefix,
        // Prompt-cache decision layer (plan §15). Safe defaults keep caching
        // effectively OFF (observe / 5m / none); the runtime reads these keys.
        CACHE_MODE: config.cacheMode,
        CACHE_TTL: config.cacheTtl,
        CACHE_ENABLED_WORKLOADS: cacheEnabledWorkloadsEnv(config),
      },
      bundling: sharedBundling,
    });
    this.feedbackQueue.grantSendMessages(this.feedbackOrchestratorFunction);

    // -----------------------------------------------------------------------
    // Feedback Engine Lambda (Python 3.12, container — AI workload via Bedrock)
    // -----------------------------------------------------------------------
    this.feedbackEngineFunction = new lambda.Function(this, "FeedbackEngineFn", {
      functionName: `${config.stackPrefix}-feedback-engine`,
      runtime: lambda.Runtime.FROM_IMAGE,
      code: lambda.Code.fromEcrImage(props.feedbackEngineRepository, {
        tagOrDigest: config.feedbackEngineImageTag,
      }),
      handler: lambda.Handler.FROM_IMAGE,
      memorySize: 1024,
      timeout: Duration.minutes(15), // long documents can exceed 5m on Bedrock
      // Reserved CAP so the longest-running function (15-min timeout, holds a
      // slot for minutes) cannot exhaust the shared account pool and starve the
      // authorizer. Aligns with the SQS maxConcurrency below (authorizer
      // throttling remediation — see lambdaConcurrency.ts).
      reservedConcurrentExecutions: config.lambdaConcurrency.feedbackEngine,
      vpc,
      vpcSubnets: privateSubnets,
      environment: {
        DB_PROXY_HOST: props.databaseProxyEndpoint,
        DB_PORT: "5432",
        DB_NAME: "appdb",
        DB_SECRET_ARN: secrets.wren_feedback_engine,
        BEDROCK_MODEL_ID: config.bedrockModelId,
        STACK_PREFIX: config.stackPrefix,
        REFERENCE_BUCKET_NAME: props.referenceBucketName,
        DOCUMENTS_BUCKET_NAME: props.documentsBucketName,
        // Prompt-cache decision layer (plan §15). Same safe defaults as the
        // orchestrator; the Python runtime reads these keys.
        CACHE_MODE: config.cacheMode,
        CACHE_TTL: config.cacheTtl,
        CACHE_ENABLED_WORKLOADS: cacheEnabledWorkloadsEnv(config),
      },
    });
    // SQS event source: the engine is triggered by messages on the feedback queue.
    this.feedbackEngineFunction.addEventSource(
      new lambdaEventSources.SqsEventSource(this.feedbackQueue, {
        batchSize: 1, // Process one feedback request at a time
        maxConcurrency: 10, // Limit concurrent engine invocations
      }),
    );

    // -----------------------------------------------------------------------
    // Diff / Anchor / Progress Lambda (Python 3.12 — pure logic)
    // -----------------------------------------------------------------------
    this.diffAnchorProgressFunction = new lambda.Function(this, "DiffAnchorProgressFn", {
      functionName: `${config.stackPrefix}-diff-anchor-progress`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: "handler.handler",
      code: lambda.Code.fromAsset(path.join(__dirname, "../../lambda/diff-anchor-progress")),
      memorySize: 512,
      timeout: Duration.seconds(60),
      vpc,
      vpcSubnets: privateSubnets,
    });

    // -----------------------------------------------------------------------
    // Notification Infrastructure (SNS topic + SQS queue + DLQ + SSM params)
    // -----------------------------------------------------------------------
    const notificationInfra = new NotificationInfraConstruct(this, "NotificationInfra", {
      stackPrefix: config.stackPrefix,
    });
    this.notificationTopicArn = notificationInfra.topic.topicArn;
    this.notificationDlq = notificationInfra.dlq;

    // -----------------------------------------------------------------------
    // Notification Service Lambda (Node 22) — processes SQS events, REST API,
    // and EventBridge scheduled override-expiry scanning.
    // -----------------------------------------------------------------------
    this.notificationFunction = new lambdaNodejs.NodejsFunction(this, "NotificationFn", {
      functionName: `${config.stackPrefix}-notification`,
      entry: path.join(monorepoRoot, "backend/notification/src/lambda-handler.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_22_X,
      memorySize: 512,
      timeout: Duration.seconds(30),
      vpc,
      vpcSubnets: privateSubnets,
      projectRoot: monorepoRoot,
      depsLockFilePath: path.join(monorepoRoot, "package-lock.json"),
      environment: {
        ...dbEnv(secrets.wren_notification),
        ...corsEnv,
        NOTIFICATION_TOPIC_ARN: notificationInfra.topic.topicArn,
        OVERRIDE_EXPIRY_WARNING_HOURS: "24",
      },
      bundling: sharedBundling,
    });

    // SQS event source: the notification Lambda is triggered by messages on the queue.
    this.notificationFunction.addEventSource(
      new lambdaEventSources.SqsEventSource(notificationInfra.queue, {
        batchSize: 5,
        maxConcurrency: 10,
      }),
    );

    // EventBridge rule: invoke every 15 minutes for override-expiry scanning.
    const overrideExpiryRule = new events.Rule(this, "OverrideExpiryRule", {
      ruleName: `${config.stackPrefix}-notification-override-expiry`,
      schedule: events.Schedule.rate(Duration.minutes(15)),
      description: "Scans for expiring/expired usage overrides to generate notifications",
    });
    overrideExpiryRule.addTarget(new targets.LambdaFunction(this.notificationFunction));

    // IAM: SNS publish (for the notification topic, though primarily used by producers)
    notificationInfra.topic.grantPublish(this.notificationFunction);

    // IAM: SSM parameter read (notification config thresholds)
    this.notificationFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ["ssm:GetParameter", "ssm:GetParameters"],
      resources: [
        `arn:aws:ssm:${this.region}:${this.account}:parameter/${config.stackPrefix}/notifications/*`,
      ],
    }));

    // Expose the notification topic ARN to other Lambdas that publish events.
    this.feedbackOrchestratorFunction.addEnvironment(
      "NOTIFICATION_TOPIC_ARN",
      notificationInfra.topic.topicArn,
    );
    notificationInfra.topic.grantPublish(this.feedbackOrchestratorFunction);

    this.adminFunction.addEnvironment(
      "NOTIFICATION_TOPIC_ARN",
      notificationInfra.topic.topicArn,
    );
    notificationInfra.topic.grantPublish(this.adminFunction);

    // -----------------------------------------------------------------------
    // AppSync Lambda authorizer (Node 22)
    // Same two-step pattern as the REST authorizer: Cognito JWT → DB identity
    // + ownership check. Deployed separately so it can be tuned independently.
    // -----------------------------------------------------------------------
    this.appSyncAuthorizerFunction = new lambdaNodejs.NodejsFunction(this, "AppSyncAuthorizerFn", {
      functionName: `${config.stackPrefix}-appsync-authorizer`,
      entry: path.join(monorepoRoot, "backend/auth/src/appSyncAuthorizer.ts"),
      handler: "handler",
      runtime: lambda.Runtime.NODEJS_22_X,
      memorySize: 256,
      timeout: Duration.seconds(20),
      // Guaranteed concurrency FLOOR for realtime auth (authorizer throttling
      // remediation — see lambdaConcurrency.ts).
      reservedConcurrentExecutions: config.lambdaConcurrency.appsyncAuthorizer,
      vpc,
      vpcSubnets: privateSubnets,
      projectRoot: monorepoRoot,
      depsLockFilePath: path.join(monorepoRoot, "package-lock.json"),
      environment: {
        ...dbEnv(secrets.wren_appsync_auth),
        COGNITO_USER_POOL_ID: props.userPoolId,
        COGNITO_CLIENT_ID: props.userPoolClientId,
        // AppSync Lambda auth uses the Cognito idToken (not accessToken).
        // The frontend sends the idToken in the Authorization header per the
        // AppSync @aws_lambda auth convention.
        COGNITO_TOKEN_USE: 'id',
      },
      bundling: sharedBundling,
    });

    // -----------------------------------------------------------------------
    // AppSync real-time API — debrief-ready notifications
    // -----------------------------------------------------------------------
    const appSyncRealtime = new AppSyncRealtimeConstruct(this, "AppSyncRealtime", {
      authorizerFunction: this.appSyncAuthorizerFunction,
      feedbackEngineRole: this.feedbackEngineFunction.role!,
      notificationLambdaRole: this.notificationFunction.role!,
      stackPrefix: config.stackPrefix,
    });
    this.appSyncGraphqlUrl = appSyncRealtime.graphqlUrl;

    // Inject the AppSync endpoint into the Feedback Engine so it can publish
    // the debriefReady mutation after writing feedback_item rows.
    this.feedbackEngineFunction.addEnvironment("APPSYNC_URL", appSyncRealtime.graphqlUrl);

    // Inject the AppSync endpoint into the Notification Lambda so it can
    // publish real-time notification mutations to subscribers.
    this.notificationFunction.addEnvironment("APPSYNC_URL", appSyncRealtime.graphqlUrl);

    // -----------------------------------------------------------------------
    // IAM: scoped roles — each function gets only what it needs
    // -----------------------------------------------------------------------
    this.grantDatabaseAccess(this.authorizerFunction, secrets.wren_authorizer);
    this.grantDatabaseAccess(this.appSyncAuthorizerFunction, secrets.wren_appsync_auth);
    this.grantDatabaseAccess(this.documentFunction, secrets.wren_document);
    this.grantDatabaseAccess(this.adminFunction, secrets.wren_admin);
    this.grantDatabaseAccess(this.auditFunction, secrets.wren_audit);

    // Activity-log pseudonym salt: read at runtime from Secrets Manager (never
    // a plaintext env var). Only the Admin and Audit Lambdas derive actor
    // pseudonyms, so only they get GetSecretValue on the salt secret.
    activityPseudonymSalt.grantRead(this.adminFunction);
    activityPseudonymSalt.grantRead(this.auditFunction);
    this.grantDatabaseAccess(this.feedbackOrchestratorFunction, secrets.wren_feedback_orch);
    this.grantDatabaseAccess(this.feedbackEngineFunction, secrets.wren_feedback_engine);
    this.grantDatabaseAccess(this.notificationFunction, secrets.wren_notification);

    // Authorizer: look up Cognito email/name when auto-provisioning app_user on first login.
    this.authorizerFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ["cognito-idp:AdminGetUser"],
      resources: [
        `arn:aws:cognito-idp:${this.region}:${this.account}:userpool/${props.userPoolId}`,
      ],
    }));

    // Document Lambda: S3 read/write for document uploads + presigned URLs.
    this.documentFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: [
        "s3:GetObject",
        "s3:PutObject",
        "s3:PutObjectTagging",
        "s3:GetObjectTagging",
        "s3:DeleteObjectTagging",
        "s3:DeleteObject",
        "s3:DeleteObjects",
      ],
      resources: [`arn:aws:s3:::${props.documentsBucketName}/*`],
    }));
    // Amazon Textract OCR (LAYOUT + TABLES analysis).
    this.documentFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: [
        "textract:AnalyzeDocument",
        "textract:StartDocumentAnalysis",
        "textract:GetDocumentAnalysis",
        // Legacy detect APIs kept for compatibility if rolled back.
        "textract:DetectDocumentText",
        "textract:StartDocumentTextDetection",
        "textract:GetDocumentTextDetection",
      ],
      resources: ["*"],
    }));
    props.storageEncryptionKey.grantEncryptDecrypt(this.documentFunction);

    // Document Lambda: DynamoDB DeleteItem to clean up conversation sessions on document deletion
    // (REQ-AUDIT-RETENTION-01 criterion 1 / REQ-AUDIT-OPSTATE-01 criterion 4).
    this.documentFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ["dynamodb:DeleteItem"],
      resources: [
        `arn:aws:dynamodb:${this.region}:${this.account}:table/${props.conversationTableName}`,
      ],
    }));

    // Admin Lambda: S3 read/write for reference material uploads.
    this.adminFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      resources: [`arn:aws:s3:::${props.referenceBucketName}/*`],
    }));
    props.storageEncryptionKey.grantEncryptDecrypt(this.adminFunction);

    // Admin Lambda: Cognito ListUsersInGroup for the sync-cognito-admins script.
    this.adminFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ["cognito-idp:ListUsersInGroup"],
      resources: [`arn:aws:cognito-idp:${this.region}:${this.account}:userpool/${props.userPoolId}`],
    }));

    // Admin Lambda: Bedrock model listing for the model config UI.
    this.adminFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ["bedrock:ListFoundationModels", "bedrock:ListInferenceProfiles"],
      resources: ["*"],
    }));

    // Admin Lambda: ApplyGuardrail for prompt injection detection on admin saves.
    this.adminFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ["bedrock:ApplyGuardrail"],
      resources: [
        `arn:aws:bedrock:${this.region}:${this.account}:guardrail/*`,
      ],
    }));

    const bedrockInvokeResources = crisBedrockInvokeResources(this.region, this.account);

    // Feedback Engine: Bedrock invoke scoped to us.anthropic.* / us.meta.* CRIS
    // (not all models/regions). A non-us.* profile will 403 until this list grows.
    this.feedbackEngineFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:GetInferenceProfile",
      ],
      resources: bedrockInvokeResources,
    }));

    // Ask WREN (Feedback Orchestrator): Bedrock + ConversationHistory DynamoDB.
    this.feedbackOrchestratorFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream",
        "bedrock:GetInferenceProfile",
      ],
      resources: bedrockInvokeResources,
    }));
    this.feedbackOrchestratorFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query",
      ],
      resources: [
        `arn:aws:dynamodb:${this.region}:${this.account}:table/${props.conversationTableName}`,
      ],
    }));
    // SSM Bedrock model id — runtime source of truth for Admin UI + invoke.
    const bedrockModelParamArn = `arn:aws:ssm:${this.region}:${this.account}:parameter${bedrockModelIdParameterName(config)}`;
    for (const fn of [this.adminFunction, this.feedbackEngineFunction, this.feedbackOrchestratorFunction]) {
      fn.addToRolePolicy(new iam.PolicyStatement({
        actions: ["ssm:GetParameter"],
        resources: [bedrockModelParamArn],
      }));
    }
    this.adminFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ["ssm:PutParameter"],
      resources: [bedrockModelParamArn],
    }));

    // ConversationHistory is SSE-KMS with the storage CMK — DynamoDB calls need decrypt/encrypt.
    props.storageEncryptionKey.grantEncryptDecrypt(this.feedbackOrchestratorFunction);

    // Feedback Engine: S3 read for documents + reference materials.
    this.feedbackEngineFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ["s3:GetObject"],
      resources: [
        `arn:aws:s3:::${props.documentsBucketName}/*`,
        `arn:aws:s3:::${props.referenceBucketName}/*`,
      ],
    }));
    this.feedbackEngineFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ["s3:ListBucket"],
      resources: [
        `arn:aws:s3:::${props.referenceBucketName}`,
      ],
    }));

    // Feedback Engine: SQS consume (read/delete messages from feedback queue).
    this.feedbackEngineFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"],
      resources: [this.feedbackQueue.queueArn],
    }));

    // -----------------------------------------------------------------------
    // Outputs
    // -----------------------------------------------------------------------
    new CfnOutput(this, "AuthorizerFunctionArn", {
      value: this.authorizerFunction.functionArn,
    });
    new CfnOutput(this, "DocumentFunctionArn", {
      value: this.documentFunction.functionArn,
    });
    new CfnOutput(this, "AdminFunctionArn", {
      value: this.adminFunction.functionArn,
    });
    new CfnOutput(this, "AuditFunctionArn", {
      value: this.auditFunction.functionArn,
    });
    new CfnOutput(this, "FeedbackOrchestratorFunctionArn", {
      value: this.feedbackOrchestratorFunction.functionArn,
    });
    new CfnOutput(this, "FeedbackEngineFunctionArn", {
      value: this.feedbackEngineFunction.functionArn,
    });
    new CfnOutput(this, "FeedbackQueueUrl", {
      value: this.feedbackQueue.queueUrl,
    });
    new CfnOutput(this, "FeedbackDlqUrl", {
      value: this.feedbackDlq.queueUrl,
    });
    new CfnOutput(this, "AppSyncAuthorizerFunctionArn", {
      value: this.appSyncAuthorizerFunction.functionArn,
    });
    new CfnOutput(this, "AppSyncGraphqlUrl", {
      value: this.appSyncGraphqlUrl,
      description: "AppSync GraphQL endpoint for real-time debrief subscriptions",
      exportName: `${config.stackPrefix}-appsync-graphql-url`,
    });
    new CfnOutput(this, "DocumentIngestQueueUrl", {
      value: this.documentIngestQueue.queueUrl,
    });
    new CfnOutput(this, "NotificationFunctionArn", {
      value: this.notificationFunction.functionArn,
    });
    new CfnOutput(this, "NotificationTopicArn", {
      value: this.notificationTopicArn,
      description: "SNS topic ARN for publishing notification events",
      exportName: `${config.stackPrefix}-notification-topic-arn`,
    });
  }

  /**
   * Grant a Lambda permission to read only its own DB secret from Secrets Manager.
   */
  private grantDatabaseAccess(fn: lambda.Function, secretArn: string): void {
    fn.addToRolePolicy(new iam.PolicyStatement({
      actions: ["secretsmanager:GetSecretValue"],
      resources: [secretArn],
    }));
  }
}
