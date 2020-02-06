## Updating

```
bosh -d ci-pipeline-cf manifest > source.yml
cp ../cf-deployment/cf-deployment.yml > target.yml
safe export secret/ci/baseline/cf > vault.yml
./migrate.sh > creds.yml
```
