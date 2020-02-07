## Updating

```
bosh -d ci-pipeline-cf manifest > source.yml
bosh int ../cf-deployment/cf-deployment.yml \
    -o ../cf-deployment/operations/use-postgres.yml \
    -o ../cf-deployment/operations/community/use-community-postgres.yml \
    -o cf-deployment-ops.yml \
    > target.yml
safe export secret/ci/baseline/cf > vault.yml
./migrate.sh > creds.yml
```
