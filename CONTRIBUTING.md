## Branching strategy

We're mainly based on Gitflow. Each branch should reflect a single task that is an individual, non-breaking, incremental improvement for the project. All new and tested functionality will go into the "develop" branch, where a release will be done to main.

The task must be appropriately defined in our Taiga project (request access if you don't have it). 

### Commits

We're using the commit message format that includes starting commit messages with imperative. Commits should be atomic pieces of working code. If many incremental, non-atomic commits are done, they can be squashed under a single one on merge. 

### Pull requests

Merged code should be incorporated to the develop branch by a pull request with an appropriate description of the changes included. Code should be checked and reviewed by peers, but no approval enforcing is made.

### Note: On guideline following
Any of these guidelines is enforced under a best-effort context. Sometimes people make mistakes and that's okay. Deadlines are enemies for quality of work, but they do exist and that's understandable. Rememeber that commit messages can be fixed with `$ git commit --amend`