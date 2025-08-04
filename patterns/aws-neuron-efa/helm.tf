data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

################################################################################
# Helm charts
################################################################################

resource "helm_release" "neuron" {
  name             = "neuron"
  repository       = "oci://public.ecr.aws/neuron"
  chart            = "neuron-helm-chart"
  version          = "1.1.1"
  namespace        = "neuron"
  create_namespace = true
  wait             = false

  # Public ECR
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password

  values = [
    <<-EOT
      nodeSelector:
        aws.amazon.com/neuron.present: 'true'
      npd:
        enabled: false
    EOT
  ]
}

resource "helm_release" "aws_efa_device_plugin" {
  name       = "aws-efa-k8s-device-plugin"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-efa-k8s-device-plugin"
  version    = "v0.5.7"
  namespace  = "kube-system"
  wait       = false

  values = [
    <<-EOT
      nodeSelector:
        vpc.amazonaws.com/efa.present: 'true'
      tolerations:
        - key: aws.amazon.com/neuron
          operator: Exists
          effect: NoSchedule
    EOT
  ]
}

resource "helm_release" "deepseek_neuron" {
  #count            = var.enable_deep_seek_neuron ? 1 : 0
  name             = "deepseek-neuron"
  chart            = "./vllm-chart"
  create_namespace = true
  wait             = false
  replace          = true
  namespace        = "deepseek"

  values = [
    <<-EOT
      image:
        repository: public.ecr.aws/z3s1x6o7/vllm-neuron
        tag: latest
        pullPolicy: IfNotPresent

      nodeSelector:
        beta.kubernetes.io/instance-type: trn1.32xlarge
      tolerations:
        - key: "aws.amazon.com/neuron"
          operator: "Exists"
          effect: "NoSchedule"

      command: "vllm serve meta-llama/Llama-2-7b-hf --device neuron --tensor-parallel-size 2 --max-num-seqs 4 --block-size 8 --use-v2-block-manager --max-model-len 2048"

      env:
        - name: NEURON_CC_FLAGS
          values: "-01"
        - name: NEURON_RT_NUM_CORES
          value: "2"
        - name: NEURON_RT_VISIBLE_CORES
          value: "0,1"
        - name: VLLM_LOGGING_LEVEL
          value: "INFO"
        - name: VLLM_USE_TRITON_FLASH_ATTN
          value: "0"
        - name: VLLM_ATTENTION_BACKEND
          value: "XFORMERS"
        - name: TRITON_DISABLE_LINE_INFO
          value: "1"
        - name: DISABLE_TRITON
          value: "1"
        - name: HUGGING_FACE_HUB_TOKEN
          value: "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"

      resources:
        limits:
          cpu: "30"
          memory: 64G
          aws.amazon.com/neuron: "1"
        requests:
          cpu: "30"
          memory: 64G
          aws.amazon.com/neuron: "1"

      livenessProbe:
        httpGet:
          path: /health
          port: 8000
        initialDelaySeconds: 1800
        periodSeconds: 10

      readinessProbe:
        httpGet:
          path: /health
          port: 8000
        initialDelaySeconds: 1800
        periodSeconds: 5
    EOT
  ]
}