Introduction to ApplicationSets in OpenShift GitOps
===

When it comes to coding, where do you store your application source files? Do you have a pet server with multiple directories to track various versions? I certainly hope you don't, and instead use some sort of Git repository for version control. So if Git works great for tracking your application source files, why would you treat your cluster infrastructure or configuration files any different?

With Git repositories as a single source of truth to provision and maintain infrastructure as code, GitOps provides the following values: 

- Consistency across any cluster, any cloud, and any on-prem environment
- Increased agility and improved reliability with visibility and version control through Git
- Increased security by adapting security best practices not only for application development but also for application delivery  

One of the most popular GitOps tools is [Argo CD](https://github.com/argoproj/argo-cd/), a CNCF project with an active community for continuous delivery through GitOps. This open-source declarative continuous delivery tool is being used in production by many large companies such as IBM, Intuit, and Major League Baseball. 

[OpenShift GitOps](http://openshift.com/gitops) is an OpenShift add-on which bundles Argo CD, and other tools, to enable teams to implement GitOps workflows for cluster configuration and application delivery. OpenShift GitOps is available as an operator in OpenShift OperatorHub, and can be installed with a simple one-click step. Once installed, users can deploy Argo CD instances via Kubernetes custom resources.

## Introduction to ApplicationSets

Integrated into OpenShift GitOps, alongside Argo CD, is the Argo CD ApplicationSet controller. [ApplicationSets](https://argocd-applicationset.readthedocs.io/en/stable/) allow you to manage deployments of a large number of applications, repositories, or clusters, all from a single Kubernetes resource, using Argo CD. 

OpenShift GitOps' ApplicationSet functionality is based on the open source [Argo CD ApplicationSet controller project](https://github.com/argoproj-labs/applicationset), hosted within the Argo CD project.
 

ApplicationSets offers a number of improvements via automation:
- Automatically deploy to multiple cluster at once, and automatically adapt to the addition/removal of clusters.
- Handle large deployments of Argo CD Applications from a single mono-repository, automatically responding to the additional/removal of new applications to the repository
- Enables development teams to manage large groups of applications securely, via self-service, without cluster administrator review, on a cluster managed via Argo CD.
 
Best of all, applications managed by the ApplicationSet controller can be managed by only *a single instance* of an ApplicationSet custom resource (CR), which means no more juggling of large numbers of Argo CD Application objects when targeting multiple clusters/repositories! 

Changes you make to this one ApplicationSet CR -- such as additions, edits, or deletions --  will automatically be deployed to all Argo CD Applications managed by that CR.


## The Argo CD Application resource

First, let's take a look at Argo CD's existing capabilities, and then we'll focus on how they can be improved by using ApplicationSets.

A simple [Argo CD Application resource](https://argoproj.github.io/argo-cd/operator-manual/declarative-setup/#applications) looks like this:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  # The Git repository we are continously deploying from, containing 
  # Kubernetes cluster resources (YAML files, Kustomize, Helm, etc.):
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: guestbook
  # The destination cluster/namespace, managed by Argo CD:
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
```

The `source` field designates the Git Repository that Argo CD is continously deploying OpenShift cluster resources *from*, and the `destination` field is the cluster/namespace that it is deploying those resources *to*.

But, if you examine the Argo CD Application above, you'll notice that you can only deploy from *one* Git repository to *one* cluster/namespace, using a single Application instance: Applications resources are 1-1 mappings between Git repositories and cluster namespaces. This means that if you wanted to deploy 10 applications to 100 clusters, it would require managing 1,000 individual Application resources (*# of clusters * # of applications*)! 

Rather than needing to keep 1,000+ individual Argo CD resources synchronized, wouldn't it be better if you could manage all of those Applications and clusters from a single resource? Fortunately, with the ApplicationSet custom resource you can!


## ApplicationSets manage large numbers of Applications through templating and automation

With Argo CD's Application resource above, we were limited to deploying from a single Git repository to a single cluster/namespace. In contrast, the ApplicationSet resource uses templates, and automated generation of template parameters, to allow you to manage many Argo CD Applications simultaneously: you can source multiple git repositories, and target multiple clusters/namespaces.

The job of the ApplicationSet controller is to watch the Argo CD namespace for ApplicationSet resource changes, and automatically generate/manage Argo CD Applications based on the ApplicationSet resource manifests. The ApplicationSet controller is a separate Kubernetes controller, installed into the same namespace as Argo CD via the OpenShift GitOps operator.

Here is an example of how to use an ApplicationSet to deploy and manage a `guestbook` application on a small number of clusters:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  generators:
  - list:
      # Parameters are generated based on this cluster list, to be
      # substituted into the template below.
      elements: 
      - cluster: engineering-dev
        url: https://1.2.3.4 # faux cluster URLs
      - cluster: engineering-prod
        url: https://2.4.6.8
      - cluster: finance-preprod
        url: https://9.8.7.6

  # 'template' is an Argo CD Application template, with support 
  # for parameter substitution using parameters generated above.
  template: 
    metadata:
      # The 'cluster' parameter from above is substituted here
      name: '{{cluster}}-guestbook'
    spec:
      project: default
      source:
        repoURL: https://github.com/argoproj-labs/applicationset.git
        targetRevision: HEAD
        # 'cluster' name is also substituted here
        path: examples/list-generator/guestbook/{{cluster}}
      destination:
        # The cluster 'url', used by Argo CD to access the cluster, is 
        # substituted here.
        server: '{{url}}'
        namespace: guestbook
```

First, take a look at the `.spec.template` field. You may notice that this looks a lot like an Argo CD Application, as seen in the previous section, and that's because *it* is an Argo CD Application!

Or more accurately, it is an Application *template*, with the exact same set of fields as the standalone Argo CD Application resource, however, the ApplicationSet template differs due to its support for the use of `{{param}}`-style template parameters. These `{{param}}` parameters may be be used to insert custom values into the template section of the resource.

Once custom parameters are inserted into the template, the template is rendered into a standalone Argo CD `Application` CR, which is applied as a Kubernetes resource to the Argo CD namespace of the cluster. In short, the template fields start as incomplete fields, then its parameters are filled in with values, and finally it is rendered and applied to the cluster.

But from where do these parameters come from? It is an ApplicationSet's *generators* that are responsible for generating these parameters. Generators produce a set of key-value pairs, which are passed into the template as those ``{{param}}``-style parameters.

Take a look at the `list` field under `.spec.generators`. The `list` field indicates we are using the *List generator* to generate parameters for our Application template. There are actually three types of generators built into the ApplicationSet controller (List, Cluster, and Git), but we'll stick with List for now.

```yaml
  - list: 
      elements: 
      - cluster: engineering-dev
        url: https://1.2.3.4
	  - (...)
```
The List generator is a very basic generator: it takes a literal list of URL and cluster values, and passes them directly as parameters to the template. The `cluster` field refers to the cluster name (as [defined within Argo CD settings](https://argoproj.github.io/argo-cd/getting_started/#5-register-a-cluster-to-deploy-apps-to-optional)), and `url` is the Kubernetes API server URL (this should also be defined within Argo CD settings).

In this example, the List generator passes 3 sets of URL/cluster pairs, one such pair is `{cluster: 'engineering-dev', url: 'https://1.2.3.4}'` ). Each set of URL/cluster pairs is rendered into the template, which results in three corresponding Argo CD Applications (one for each defined cluster).

After the ApplicationSet is applied to the cluster, here is how the generated Applications look within the Argo CD Web UI:
![](https://i.imgur.com/w2cWpji.png)

While basic, the List generator can still be effective, as adding or removing new values from this list will immediately have a corresponding effect on all targetted clusters: new clusters added to the `list` will automatically have templated Applications deployed to them, and clusters removed from the list will likewise have the Application resources removed.

With the List generator, managing the deployment of Argo CD Applications, and keeping them synchronized, is as easy as modifying that single ApplicationSet resource. But what are our other options for defining target clusters?

## The Cluster generator

Rather than just using a fixed, literal list of clusters to deploy to, we can use the *Cluster generator* to automatically deploy to all of the clusters managed by Argo CD:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  generators:
  - clusters: {} # Automatically use all clusters defined within Argo CD
  template:
    metadata:
      name: '{{name}}-guestbook' # 'name' field of the Secret
    spec:
      project: "default"
      source:
        repoURL: https://github.com/argoproj/argocd-example-apps/
        targetRevision: HEAD
        path: guestbook
      destination:
        server: '{{server}}' # 'server' field of the secret
        namespace: guestbook
```

With this example, as new clusters are added or removed, the parameters generated by the Cluster generator are regenerated by the ApplicationSet controller. This causes new Applications targeting these clusters to be created, and Applications targeting deleted clusters to be removed.

This automation removes the burden of adding or removing new clusters by hand, and further generator customizations are available for targeting a subset of clusters (for example, staging versus production). You can learn more about the Cluster generator within the [Cluster generator documentation](https://argocd-applicationset.readthedocs.io/en/stable/Generators/#cluster-generator).

## The Git Generator

The third type of generator is the Git generator, which generates new Argo CD Applications based on commits within a Git repository.  The Git generator has two subtypes, the Git directory generator, and the Git file generator. First, let's look at the Git directory generator.

The [Git directory generator](https://argocd-applicationset.readthedocs.io/en/stable/Generators/#git-generator-directories) generates template parameters by scanning through directories in a Git repository, looking for resources to deploy:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
spec:
  generators:
  - git:
      # Repository to scan
      repoURL: https://github.com/argoproj-labs/applicationset.git
      revision: HEAD
      # Scan through directories matching path this expression, for 
      # applications to deploy:
      directories:
      - path: examples/git-generator-directory/cluster-addons/*
# (...)
```
This example scans through the [`cluster-addons` path of a Git repository](https://github.com/argoproj-labs/applicationset/tree/release-0.1.0/examples/git-generator-directory), looking for application paths that match the specified path expression. Matching application paths will be passed to the template as paths, rendered into Argo CD Applications, and deployed via Argo CD. 

The Git directory generator is great for Git repositories containing application resources where each application is organized within its own directory, and the entire repository targets a single cluster. The ApplicationSet controller will automatically pull the latest commits from the repository, and update the cluster's Argo CD Applications based on data gathered from directories within the repository.

In contrast, the [Git file generator](https://argocd-applicationset.readthedocs.io/en/stable/Generators/#git-generator-files) scans through *files* within a Git repository, looking for matching JSON files:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: guestbook
spec:
  generators:
  - git:
      repoURL: https://github.com/argoproj-labs/applicationset.git
      revision: HEAD
      files:
      # Scan through files on this path, looking for JSON files to parse.
      - path: "examples/git-generator-files-discovery/cluster-config/**/config.json"
# (...)
```
JSON files that match the path expression are parsed and provided as key/values to the Application template. This allows the Application deployment metadata to be managed through Git pull/merge requests, with the JSON files containing the values which will be rendered into the template.

The Git file generator is great for providing more fine-grained control over the generated Applications than is possible with the other generators, and for allowing secure, self-service usage of Argo CD by tenants of a cluster. See the [Git file generator](https://argocd-applicationset.readthedocs.io/en/stable/Generators/#git-generator-files) documentation for more information.

## Installation

The ApplicationSet feature is bundled with the OpenShift GitOps operator, but must be enabled via the `ArgoCD` operand. To ensure that the ApplicationSet feature is enabled, add the `applicationSet: {}` YAML field to the ArgoCD operand, like below on line 10:

![](https://i.imgur.com/0YQrvCQ.png)

You may also make this change from the CLI, using:

`oc edit ArgoCD/<ArgoCD instance name> -n <namespace>`

To verify that the ApplicationSet feature is enabled within the ArgoCD instance, check the `applicationSet` field of the ArgoCD resource. Within the OpenShift Operator Hub, select the Red Hat OpenShift GitOps operator and select the `ArgoCD` operand.

Under the YAML tab, ensure that `applicationSet: {}` is included in the operand YAML, as seen below, on line 120:

![](https://i.imgur.com/XQKCYM6.png)

To disable the ApplicationSet feature, simply remove the `applicationSet: {}` field within the YAML (i.e. reverse the installation steps).

## Resources

We hope you've enjoyed this quick introduction to the power and flexibility through automation and templating, that is available with ApplicationSets! Learn more about ApplicationSets, GitOps, OpenShift, and more, from the resources below.

#### Further resources:
- [ApplicationSet Documentation](https://argocd-applicationset.readthedocs.io/): Detailed documention on ApplicationSet generators, templates, use cases, and more.
- [Getting Started with ApplicationSets on OpenShift.com](https://www.openshift.com/blog/getting-started-with-applicationsets): A detailed introduction to the ApplicationSet feature set.
- [OpenShift Pipelines and OpenShift GitOps are now Generally Available](https://www.openshift.com/blog/openshift-pipelines-and-openshift-gitops-are-now-generally-available): Introduction to Argo CD and Tekton on OpenShift.
- [Introduction to GitOps on OpenShift](https://www.openshift.com/learn/topics/gitops/): Learn more about the benefits of GitOps, and how Red Hat OpenShift enables the GitOps philosophy.
- [ApplicationSet Project Repository](https://github.com/argoproj-labs/applicationset): The open source ApplicationSet project GitHub repository, hosted within the Argo CD project.

