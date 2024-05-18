# Deploy

This tool allows you to deploy multiple apps to same server

# Requirements

There are two ENV variables needed to this tool to work:
``` bash
DEPLOY_SERVER # Name of the server, where you want to deploy your apps
IMAGE_REPOSITORY_PREFIX # Prefix for deploy image
SERVICE_DEFINITION_FILE # Docker-compose file defining available services
```
