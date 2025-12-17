import boto3
import json

def get_rds_cluster_secret_passwords(account_ids):
    region = "us-east-1"  # Adjust the region if your secrets are in a different region

    for account_id in account_ids:
        print(f"\nProcessing account: {account_id}")

        # 1. Assume Role in the Account
        try:
            session = boto3.Session(region_name=region)
            sts = session.client("sts")
            response = sts.assume_role(
                RoleArn=f"arn:aws:iam::{account_id}:role/sql-deploy-automation-iam-role",
                RoleSessionName="sqlteam"
            )
            creds = response['Credentials']
            new_session = boto3.Session(
                aws_access_key_id=creds['AccessKeyId'],
                aws_secret_access_key=creds['SecretAccessKey'],
                aws_session_token=creds['SessionToken'],
                region_name=region
            )
        except Exception as e:
            print(f"Error assuming role in {account_id}: {e}")
            continue

        # 2. List rds!cluster Secrets
        secretsmanager = new_session.client("secretsmanager")
        rdscluster_secret_info = []
        try:
            paginator = secretsmanager.get_paginator('list_secrets')
            for page in paginator.paginate():
                for secret in page['SecretList']:
                    name = secret['Name']
                    description = secret.get('Description', '')
                    if 'rds!cluster' in name:
                        rdscluster_secret_info.append((name, description))
        except Exception as e:
            print(f"Error listing secrets in {account_id}: {e}")
            continue

        if not rdscluster_secret_info:
            print("No secrets found containing 'rds!cluster'.")
            continue

        print(f"\nSecrets containing 'rds!cluster':")
        # 3. Print Info and Secret Values
        for name, description in rdscluster_secret_info:
            try:
                secret_value_response = secretsmanager.get_secret_value(SecretId=name)
                secret_string = secret_value_response.get('SecretString')
                if not secret_string:
                    print(f"  Secret {name} has no SecretString.")
                    continue

                try:
                    secret_data = json.loads(secret_string)
                except Exception as json_exc:
                    print(f"  Could not parse secret JSON for {name}: {json_exc}")
                    continue

                username = secret_data.get('username')
                host = secret_data.get('host')
                password = secret_data.get('password')
                print(f"""  Secret Name: {name}
    Description: {description}
    username: {username}
    host: {host}
    password: {password}
""")
            except Exception as e:
                print(f"  Error retrieving secret {name}: {e}")

if __name__ == "__main__":
    # Replace these with your AWS Account IDs
    account_ids = ["65656565656", "656565656565"]
    get_rds_cluster_secret_passwords(account_ids)
