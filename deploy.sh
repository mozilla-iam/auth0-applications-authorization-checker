#!/bin/bash -e

# path/to/example.yaml
TEMPLATE_FILENAME=$1
# DEV_LAMBDA_CODE_STORAGE_S3_BUCKET_NAME
S3_BUCKET=$2
# ExampleStackName
STACK_NAME=$3
# s3-path-prefix
S3_PREFIX=$4
S3_PREFIX_ARG="--s3-prefix $S3_PREFIX"

# Confirm that we have access to AWS
set +e
result="$(aws sts get-caller-identity --output text 2>&1)"
if ! echo "$result" | grep 'arn:aws:sts' >/dev/null; then
  echo "Error : $result"
  exit 1
fi
set -e

# This tempfile is required because of https://github.com/aws/aws-cli/issues/2504
TMPFILE="$(mktemp).yaml"
TMPDIR=$(mktemp -d)
TARGET_PATH="`dirname \"${TEMPLATE_FILENAME}\"`"
ln -n -f -s $TMPDIR "${TARGET_PATH}/build"
trap "{ rm -v -f $TMPFILE;rm -f -r $TMPDIR;rm -v -f \"${TARGET_PATH}/build\"; }" EXIT

# https://unix.stackexchange.com/a/180987/22701
cp -v -R "${TARGET_PATH}/functions/." "${TARGET_PATH}/build/"

aws cloudformation package \
  --template $TEMPLATE_FILENAME \
  --s3-bucket $S3_BUCKET \
  $S3_PREFIX_ARG \
  --output-template-file $TMPFILE

if [ "$(aws cloudformation describe-stacks --query "length(Stacks[?StackName=='${STACK_NAME}'])")" = "1" ]; then
  # Stack already exists, it will be updated
  wait_verb=stack-update-complete
else
  # Stack doesn't exist it will be created
  wait_verb=stack-create-complete
fi

set +e
if aws cloudformation deploy --template-file $TMPFILE --stack-name $STACK_NAME \
    --capabilities CAPABILITY_IAM; then
  echo "Waiting for stack to reach a COMPLETE state"
  if aws cloudformation wait $wait_verb --stack-name  $STACK_NAME; then
    if [ "$OUTPUT_VAR_NAME" ]; then
      aws cloudformation describe-stacks --stack-name $STACK_NAME --query "Stacks[0].Outputs[?OutputKey=='${OUTPUT_VAR_NAME}'].OutputValue" --output text
    fi
    exit 0
  fi
fi
aws cloudformation describe-stack-events \
  --stack-name $STACK_NAME \
  --query 'StackEvents[?ends_with(ResourceStatus, `_FAILED`)].[LogicalResourceId, ResourceType, ResourceStatusReason]' \
  --output text
exit 1