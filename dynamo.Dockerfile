FROM arm64v8/amazoncorretto:11

WORKDIR /app

# Install dependencies
RUN yum install -y \
    shadow-utils \
    curl \
    unzip \
    python3 \
    python3-pip \
    tar \
    gzip && \
    yum clean all

# Download and extract DynamoDB Local
RUN curl -sL https://s3.us-west-2.amazonaws.com/dynamodb-local/dynamodb_local_latest.tar.gz -o dynamodb.tar.gz && \
    mkdir /app/dynamodb && \
    tar -xzf dynamodb.tar.gz -C /app/dynamodb && \
    rm dynamodb.tar.gz

# Move DynamoDBLocal.jar and lib folder to /app
RUN mv /app/dynamodb/DynamoDBLocal.jar /app/ && \
    mv /app/dynamodb/DynamoDBLocal_lib /app/ && \
    rm -rf /app/dynamodb

# Install AWS CLI
RUN curl -sL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" && \
    unzip -q awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws

# Environment
ENV AWS_ACCESS_KEY_ID=GOSYNC
ENV AWS_SECRET_ACCESS_KEY=GOSYNC
ENV AWS_ENDPOINT=http://localhost:8000
ENV AWS_REGION=us-west-2
ENV TABLE_NAME=client-entity-dev
ENV PATH="/usr/local/bin:$PATH"

# Copy schema
COPY schema/dynamodb/ /app
RUN mkdir -p /app/db

# Schema setup during build using correct java command
RUN java -Djava.library.path=./DynamoDBLocal_lib \
         -cp DynamoDBLocal.jar:./DynamoDBLocal_lib/* \
         com.amazonaws.services.dynamodbv2.local.main.ServerRunner \
         -sharedDb -inMemory & \
    DYNAMO_PID=$! && \
    echo "Waiting for DynamoDB Local to start..." && \
    sleep 10 && \
    echo "Creating table..." && \
    aws dynamodb create-table --cli-input-json file:///app/table.json \
      --endpoint-url $AWS_ENDPOINT --region $AWS_REGION && \
    echo "Enabling TTL..." && \
    aws dynamodb update-time-to-live --table-name $TABLE_NAME \
      --time-to-live-specification "Enabled=true, AttributeName=ExpirationTime" \
      --endpoint-url $AWS_ENDPOINT --region $AWS_REGION && \
    kill $DYNAMO_PID

# Optional healthcheck
HEALTHCHECK --interval=5s --timeout=3s --retries=3 \
  CMD curl -f http://localhost:8000 || exit 1

WORKDIR /app

# Final CMD — run DynamoDB Local correctly
CMD ["sh", "-c", "\
  java -Djava.library.path=./DynamoDBLocal_lib \
       -cp DynamoDBLocal.jar:./DynamoDBLocal_lib/* \
       com.amazonaws.services.dynamodbv2.local.main.ServerRunner \
       -sharedDb -dbPath /app/db"]
