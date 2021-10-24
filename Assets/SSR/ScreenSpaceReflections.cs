using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[Serializable]
internal class ScreenSpaceReflectionsSettings
{
    [SerializeField] [Range(0.001f, 1.0f)] internal float Intensity = 3.0f;
    [SerializeField] [Range(1f, 10.0f)] internal float FallOff = 3.0f;
    [SerializeField] [Range(0.1f, 3.0f)] internal float MaxDistance = 3.0f;
    [SerializeField] [Range(1f, 50.0f)] internal float Resolution = 3.0f;

    [SerializeField] [Range(1f, 300.0f)] internal float DisqualificationDepthDelta = 3.0f;
}

[DisallowMultipleRendererFeature]
internal class ScreenSpaceReflections : ScriptableRendererFeature
{
    [SerializeField, HideInInspector] private Shader shader = null;
    [SerializeField] private ScreenSpaceReflectionsSettings m_Settings = new ScreenSpaceReflectionsSettings();

    private Material material;
    private ScreenSpaceReflectionsPass SsrPass = null;

    private const string shaderName = "Hidden/ScreenSpaceReflections";

    public override void Create()
    {
        if (SsrPass == null)
        {
            SsrPass = new ScreenSpaceReflectionsPass();
        }

        GetMaterial();
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (!GetMaterial())
        {
            Debug.LogErrorFormat(
                "{0}.AddRenderPasses(): Missing material. {1} render pass will not be added. Check for missing reference in the renderer resources.",
                GetType().Name);
            return;
        }

        bool shouldAdd = SsrPass.Setup(m_Settings);
        if (shouldAdd)
        {
            SsrPass.ConfigureInput(ScriptableRenderPassInput.Color);
            SsrPass.ConfigureInput(ScriptableRenderPassInput.Normal);
            SsrPass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;

            renderer.EnqueuePass(SsrPass);
        }
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(material);
    }

    private bool GetMaterial()
    {
        if (material != null)
        {
            return true;
        }

        if (shader == null)
        {
            shader = Shader.Find(shaderName);
            if (shader == null)
            {
                return false;
            }
        }

        material = CoreUtils.CreateEngineMaterial(shader);
        SsrPass.material = material;
        return material != null;
    }

    private class ScreenSpaceReflectionsPass : ScriptableRenderPass
    {
        const string ProfilerTag = "SSR";
        internal Material material;

        private ProfilingSampler m_ProfilingSampler = new ProfilingSampler(ProfilerTag);
        private ScreenSpaceReflectionsSettings m_CurrentSettings;
        private RenderTargetIdentifier SsrTexture_D = new RenderTargetIdentifier(s_SsrTexture);
        private RenderTargetIdentifier BaseMap = new RenderTargetIdentifier(s_BaseMapID);
        private RenderTargetIdentifier colorBuffer;

        private RenderTextureDescriptor m_Descriptor;

        private static readonly int s_BaseMapID = Shader.PropertyToID("_BaseMap");
        private static readonly int s_SSRParams1ID = Shader.PropertyToID("_SSR_Params1");
        private static readonly int s_SSRParams2ID = Shader.PropertyToID("_SSR_Params2");
        private static readonly int s_SsrTexture = Shader.PropertyToID("_SSR_Texture");


        internal ScreenSpaceReflectionsPass()
        {
            m_CurrentSettings = new ScreenSpaceReflectionsSettings();
        }

        internal bool Setup(ScreenSpaceReflectionsSettings featureSettings)
        {
            m_CurrentSettings = featureSettings;

            return material != null
                && m_CurrentSettings.Intensity > 0.0f && m_CurrentSettings.FallOff > 0.0f;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            RenderTextureDescriptor cameraTargetDescriptor = renderingData.cameraData.cameraTargetDescriptor;

            Vector4 ssrParams1 = new Vector4(
                m_CurrentSettings.Intensity,
                m_CurrentSettings.FallOff,
                m_CurrentSettings.MaxDistance,
                m_CurrentSettings.Resolution
            );

            Vector4 ssrParams2 = new Vector4(
                0,0,m_CurrentSettings.DisqualificationDepthDelta,0
            );

            material.SetVector(s_SSRParams1ID, ssrParams1);
            material.SetVector(s_SSRParams2ID, ssrParams2);

            m_Descriptor = cameraTargetDescriptor;
            m_Descriptor.msaaSamples = 1;
            m_Descriptor.depthBufferBits = 0;

            colorBuffer = renderingData.cameraData.renderer.cameraColorTarget;
            
            cmd.GetTemporaryRT(s_BaseMapID, m_Descriptor, FilterMode.Bilinear);
            m_Descriptor.colorFormat = RenderTextureFormat.ARGB32;
            cmd.GetTemporaryRT(s_SsrTexture, m_Descriptor, FilterMode.Bilinear);
            ConfigureTarget(s_SsrTexture);
            ConfigureTarget(BaseMap);
            ConfigureClear(ClearFlag.None, Color.white);
        }


        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            if (material == null)
            {
                Debug.LogErrorFormat("{0}.Execute(): Missing material. {1} render pass will not execute. Check for missing reference in the renderer resources.", GetType().Name);
                return;
            }
            CommandBuffer cmd = CommandBufferPool.Get();
            
            using (new ProfilingScope(cmd, m_ProfilingSampler))
            {
                cmd.Blit(colorBuffer, BaseMap);
                 cmd.SetGlobalTexture(s_BaseMapID, BaseMap);
                 cmd.SetRenderTarget(
                      SsrTexture_D,
                      RenderBufferLoadAction.DontCare,
                      RenderBufferStoreAction.Store,
                      SsrTexture_D,
                      RenderBufferLoadAction.DontCare,
                      RenderBufferStoreAction.DontCare
                  );

                 cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, material, 0, 0);

                cmd.SetRenderTarget(
                    colorBuffer,
                    RenderBufferLoadAction.DontCare,
                    RenderBufferStoreAction.Store,
                    colorBuffer,
                    RenderBufferLoadAction.DontCare,
                    RenderBufferStoreAction.DontCare
                );

                cmd.SetGlobalTexture(s_SsrTexture, SsrTexture_D);
                
               cmd.DrawMesh(RenderingUtils.fullscreenMesh, Matrix4x4.identity, material, 0, 1);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            if (cmd == null)
            {
                throw new ArgumentNullException("cmd");
            }

            cmd.ReleaseTemporaryRT(s_SsrTexture);
        }
    }
}

