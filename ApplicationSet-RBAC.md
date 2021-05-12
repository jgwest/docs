# ApplicationSets: Adding support for CLI/Web requests, and handling RBAC

*Assumptions*: ApplicationSet controller remains an independent, standalone microservice from Argo CD. 
- It may be beneficial to move ApplicationSet controller code into the Argo CD codebase, at some point in the future, but it is not required to implement this feature.
    - Why beneficial to merge the codebases? Less chance that Argo CD will change something that breaks AppSet controller, or vice versa. Integrated testing infrastructure to reduce incompatibilities. Same release schedule. Etc.
- Likewise, it may be beneficial to include AppSet controller in the default Argo CD install, but it's up to you all if/when to pull that particular lever. For the purposes of this feature, I've maintained it as optional.
- Both of these are orthorgonal to this feature, but would affect its design.


## Architecture: Creation of ApplicationSet via Argo CD Command/Web UI creation flow (respecting RBAC)

![](https://i.imgur.com/aOPSBFk.png)


This is the high level overview of creation (update/deletion) of an ApplicationSet via Argo CD CLI.

#### User issues command from CLI, into an Argo CD server on which they are logged-in:
1) User issues `argocd appset create/update/delete` command (or Web UI equivalent)
    - `argocd appset` command converts the command request into GRPC and sends it off to Argo CD API Server

#### Argo CD API Server:
2) Receives Create/Update/Delete request via GRPC
3) API server verifies that ApplicationSet controller is installed within the namespace (if not, return an error response back to user)
    - Look for Pod with appropriate ApplicationSet `annotation`
    - This is required because this proposal assumes that ApplicationSet controller is an optional install.
4) Send the GRPC request to the ApplicationSet controller via GRPC
    - Include authentication information from the user in the request

(... the process continues within the ApplicationSet controller...)

#### ApplicationSet controller:
5) ApplicationSet controller receives Create/Update/Delete GRPC
    - *These next steps will be a create example, but update and delete are similar.*
7) Ensure user has appropriate RBAC to run the generator:
    - Verify that the user can access the Git repository (for Git generators)
    - Verify that user has cluster access (to see the clusters, for Cluster generator)
    - (etc)
8) Verify that the user has permission to create/update/delete (depending on the request type) at least one Application within the RBAC policy
    - We want to prevent the generators being invoked by users that don't have permissions to create any Applications (since generators or templates might be exploited to DoS the ApplicationSet controller, using a malicious ApplicationSet)
9) Run the generator, and render the parameters into the template.
10) Look at the generated Applications (but don't apply them yet!), and verify that user has the required RBAC permissions to perform the required actions
11) Finally, apply the ApplicationSet (not the Applications), and the Applications, to the namespace.

## Should we add a new 'applicationset' RBAC resource?

#### Do we need to add a new RBAC resource for applicationsets, alongside [the existing ones](https://argoproj.github.io/argo-cd/operator-manual/rbac/)? (clusters, projects, applications, repositories, certificates, accounts, gpgkeys)
- I don't think we do.
- If we DID add a new RBAC resource, this would require application administrators...
    - ... to add a new ApplicationSet resource to the RBAC policy list, alongside their existing Application policies
    - ... and to keep the ApplicationSet and Application RBAC policy lists in sync
- Or, said another way: I expect that there are very few (if any) cases where a user would need to be able to create an Application, but not be able to create an ApplicationSet (and vice versa)
- When it comes to security, the less moving parts the better (with some minor loss in flexibility, eg the ability to specifically prevent access to ApplicationSet resource)

#### If there is no RBAC resource for applicationsets, how do we control access to them?
- Instead of an `applicationset` rbac resource, we instead examine the Applications that are owned by the applicationset
- An ApplicationSet inherits permissions from its children

### RBAC ApplicationSet creation algorithm

- Described in the introduction.

### RBAC ApplicationSet deletion algorithm

A user is only able to delete an ApplicationSet if they have permissions to delete all of the Applications managed by the ApplicationSet.
- For deletion we don't need to run the generate/template algorithm, we just look at the Applications that are already managed by the ApplicationSet.

#### The algorithm is, if the user attempts to delete an ApplicationSet via Web UI/CLI:
- This check is performed in ApplicationSet controller, on receiving a delete request via GRPC from API server.
- For each application owned by the ApplicationSet that the user is attempting to delete:
    - Check if the user has delete permission on the Application
    - Check if the user has delete permission within the project (?)
    - If the user does NOT have permission on least one of these, the operation should fail.
- On pass, ApplicationController server deletes (ie `kubectl delete`) the ApplicationSet resource.


### RBAC ApplicationSet update algorithm

A user can only update an ApplicationSet IF the user has permission to update all of the Applications currently owned by the ApplicationSet.
- When the user makes a change to an ApplicationSet, we assume that it's possible that the change it might affect any or all of the Applications, and thus we require the user to have write access to all of those Applications.
- We likewise check that the resulting generated Applications are also compliant with the user's permissions.

#### Algorithm is, if the user attempts to update an ApplicationSet via Web UI/CLI:
- ApplicationSet controller receives a request to update an ApplicationSet from API server
- The ApplicationSetController looks at all the Applications owned by the ApplicationSet (via ownerref or annotation):
    - Verify that the user has permission to act on all of the Applications currently managed by the ApplicationSet
- If the above precondition is met, proceed to the next step, otherwise fail.
- The ApplicationSet is generated and rendered into a template
    - All the same checks done by the Create workflow, described above, are done here (user can access repo, cluster, etc)
- Finally, on success, the API server applies (`kubectl apply`) the requested change to the ApplicationSet (and the Applications).


### ApplicationSets and AppProjects

An important design contraint in this area: ApplicationSets do not belong to projects. They generate Applications that are a part of projects, but they themselves are not part of a project.

#### Why not just include a project field on ApplicationSet CR?
A single ApplicationSet has the power to produce Applications within multiple projects, so it does not necessarily make sense to include an ApplicationSet within a single project.

#### Why not just include a projects field (array of strings) on ApplicationSets, to allow it to belong to multiple projects?

This is getting closer to ideal, but still limits the expressive power of the ApplicationSet: it requires a user to specify, up front, what projects they expect to generate applications for. Eg you must statically define an ApplicationSet's projects.

This excludes the scenario where the projects that a particular ApplicationSet will generate Applications for is truly dynamic, eg coming from a configuration file in Git, and thus not known at creation.

#### We still need a way to limit the scope of user actions against  ApplicationSets

Even though ApplicationSets don't belong to a project, we still need to prevent users from modifying ApplicationSets that they don't have RBAC access to.

By looking at the projects of child objects, we achieve the same goal, but while maintaining the flexibility of allowing

Why? We don't want users to be able to delete ApplicationSets that they don't have RBAC access to (because that allow users to delete applications they don't have access to... BAD!); BUT, since ApplicationSets don't have a project, we need some way to tell what applications/projects an ApplicationSet manages. So we use the applications and projects within it.



## Command design

```
argocd appset create "(filename.yaml)"
argocd appset delete "(applicationset resource name)"
argocd appset apply  "(filename.yaml)"
```

This proposal assumes that the ApplicationSet controller is still an optional, standalone install. Thus all `argocd appset` commands should fail if the ApplicationSet controller is not installed. (The Argo CD API server would check if the ApplicationServer is running by looking for a deployment with a specific 'applicationset controller' annotation, or similar mechanism.)

This command proposal differs significantly from how the `argocd app create` command is designed: notice the lack of parameters to `appset create/apply` besides the filename. Rather than creating an application(set) by [adding support for a large number of parameters](https://argoproj.github.io/argo-cd/user-guide/commands/argocd_app_create/), eg: 
- `argocd app create guestbook --repo https://github.com/argoproj/argocd-example-apps.git --path guestbook --dest-namespace default --dest-server https://kubernetes.default.svc --directory-recurse`

Instead `appset create` and `appset apply` will just take as a parameter, a path to a YAML file, in the form of a standard ApplicationSet CR:
```yaml
# cluster-addons.yaml:
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
spec:
  generators:
  - git:
      repoURL: https://github.com/argoproj-labs/applicationset.git
      revision: HEAD
      directories:
      - path: examples/git-generator-directory/cluster-addons/*
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj-labs/applicationset.git
        targetRevision: HEAD
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'

# Create the above ApplicationSet
argocd appset create cluster-addons.yaml
```

In general, the reason to use YAML is that CLI parameters aren't a good fit for allowing the user to fully express what can be represented with an ApplicationSet resource.

#### Why use YAML file, over CLI params
- Easier for users to specify a YAML file, than specifying a bunch of parameters
    - By my count, if creating an ApplicationSet using parameters, it would take at least 8 parameters (16 arguments) 
    - For example, the above ApplicationSet would look like: `appset create --name cluster-addons --gitGeneratorRepoURL "repo url" --gitGeneratorRevision "HEAD" --gitGeneratorDirectory "examples/git-generator-directory/cluster-addons/*"  --templateMetadataName "{{path.basename}}" --templateProject "default" --templateSrcRepoURL "https://github.com/argoproj-labs/applicationset.git" --templateSrcRevision "HEAD" --templateSrcPath "{{path}}" --templateDestServer "https://kubernetes.default.svc" --templateDestNamespace "{{path.basename}}" `
- Matrix generator is especially tough to represent with parameters, as it takes two generators as input, eg: 
```yaml
spec:
  generators:
  - matrix:
      generators:
        - git:
            name: cluster-deployments	
            repoURL: https://github.com/argoproj-labs/applicationset.git
            revision: HEAD
            directories:
            - path: examples/proposal/matrix/cluster-addons/*
        - clusters:
            selector:
              matchLabels:
                argocd.argoproj.io/secret-type: cluster
```

- Likewise, tough to get full expressive power of YAML, due to support for arrays of generators:
```yaml
spec:
  generators:
  - list: 
    # (...)
  - list:
    # (...)
  - list:
    # (...)    
```
- Increased tension with backwards/forwards compatibility between Argo CD CLI and ApplicationSet controller
    - It would be possible to get into a situation where the Argo CD CLI was newer/older than the version of ApplicationSet controller installed, and thus it advertised support for parameters/generators that the ApplicationSet did not support (or vice versa).
        - OTOH this just means that API server will just report a failure, due to CRD validation of the created object.
    - This would not be an issue if ApplicationSet controller moved into Argo CD codebase (and thus the versions would always be equivalent).
- `appset create` would need to include ALL the options in [argocd app create](https://argoproj.github.io/argo-cd/user-guide/commands/argocd_app_create/) to represent the same expressive power, and this is a lot of up front work.
- ApplicationSet is still maturing, and is more likely to break things than the more mature Argo CD:
    - Each substantial change to a generator or schema would require a corresponding substantial change to a CLI command; if we had to maintain a bunch of commands for a bunch of generators, this increases the cost of making changes to those generators (as part of the maturation process)
    - Likewise, new generators are being added (and thus new parameters are likely to be required for these generators)


#### Why use CLI params, instead of YAML:
- Users might be more familiar with Argo CD CLI style commands
- Some folks are less literate in YAML, and thus don't grok YAML's hierarchy/parsing rules
- CLI has the advantage of hiding the hierarchy (for better or worse)


### Alternatives considered (CLI)

Rather than using Argo CD's CLI, we could create a new AppSet CLI "`appset`" that would communicate directly with the ApplicationSet deployment, rather than going through the Argo CD API Server as an intermediary (though if we were adding web UI support, this would still be required regardless).

However, I don't think the world needs yet another CLI 🙂, and I'm not sure there is much of a value add. The only advantage would be separation of the logic between the two projects, and ability to evolve them independently.


## UI architectural flow and design

The UI architectural flow would be roughly equivalent to the CLI design: the UI will communicate Create/Delete/Update commands to the Argo CD API server using (roughly) the same API as the CLI.

As for the design of the UI itself, it sounds like Intuit folks have some ideas on how best to integrate ApplicationSet capabilities into the existing Argo CD web interface.

A couple things I would note:

1) This proposal assumes that the ApplicationSet controller is an optional, standalone install, with some tolerance for backward/forwards compatibilty: This requirement is straightforward to handle with a CLI, but more difficult to handle with a proper UI (which has many more moving parts), so if we are looking for full ApplicationSet UI integration with Argo CD, we may want to consider closer codebase integration.

2) The ApplicationSet CR contains a lot of flexibility, which is likely to further evolve as more generators are added. This complexity might be difficult to fully express in web UI (or at least w/o an equally complex web UI implementation).

