terraform init -backend-config="key=tk/tf-coaching17-infra-dev.tfstate" -reconfigure
terraform apply -var-file="envs/dev.tfvars" --auto-approve

terraform init -backend-config="key=tk/tf-coaching17-infra-uat.tfstate" -reconfigure
terraform apply -var-file="envs/uat.tfvars" --auto-approve

terraform init -backend-config="key=tk/tf-coaching17-infra-prod.tfstate" -reconfigure
terraform apply -var-file="envs/prod.tfvars" --auto-approve