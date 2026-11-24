window.MODEL_MISSION_CATALOGS = {
  updatedAt: "2026-11-24T06:34:18-05:00",
  platforms: {
    copilot: {
      confidence: "account-observed",
      source: "Authenticated Microsoft 365 Copilot Chat picker captured (2026-11-24); exact picker state IDs from UI options: Auto=Magic, Quick response=Chat, Think deeper=Reasoning, Advanced reasoning=DeepWork, Grok 4.6=Grok_Reasoning, Claude Sonnet 5.5=Claude_Sonnet, Opus 5.5=Claude_Opus, Fable 5.1=Claude_Fable, MAI=Mai_Auto, GPT-5.6 Sol Quick response=Gpt_5_6_Chat, GPT-6=Gpt_6_Sol_Chat, GPT-5.6 Sol Think deeper=Gpt_5_6_Reasoning, GPT-6.2 Sol=Gpt_62_Sol_Reasoning, GPT-6.2 Astra=Gpt_62_Astra_Reasoning. Model fusion also exposes Compare=Forum and Critique=Enhance (not model choices).",
      models: [
        "Magic",
        "Chat",
        "Reasoning",
        "DeepWork",
        "Grok_Reasoning",
        "Claude_Sonnet",
        "Claude_Opus",
        "Claude_Fable",
        "Mai_Auto",
        "Gpt_5_6_Chat",
        "Gpt_6_Sol_Chat",
        "Gpt_5_6_Reasoning",
        "Gpt_62_Sol_Reasoning",
        "Gpt_62_Astra_Reasoning"
      ]
    },
    cowork: {
      confidence: "account-observed",
      source: "Authenticated Microsoft 365 Copilot Cowork picker and /v1/models response captured (2026-11-24): Auto value=auto; Fast toggle name=autoFast; Claude IDs: opus-5.5, opus-5.5-fast, sonnet-5.5; GPT IDs: gpt-6.2-astra, gpt-6.2-sol-substrate, gpt-6.2-sol-fast.",
      models: [
        "auto",
        "autoFast",
        "opus-5.5",
        "opus-5.5-fast",
        "sonnet-5.5",
        "gpt-6.2-astra",
        "gpt-6.2-sol-substrate",
        "gpt-6.2-sol-fast"
      ]
    },
    scout: {
      confidence: "live-exact",
      source: "Microsoft Scout m_list_models (2026-11-24)",
      models: [
        "auto",
        "claude-sonnet-5",
        "claude-haiku-4.5",
        "gpt-5.6-sol",
        "gpt-5.6-luna",
        "gpt-5.3-codex",
        "claude-haiku-5.5",
        "claude-sonnet-5.5",
        "gemini-3.8-flash",
        "gemini-4-argon",
        "gemini-4-carbon",
        "gemini-4-hydrogen",
        "gemini-4-neon",
        "gpt-5.6-sol-fast",
        "gpt-6.1-sol",
        "gpt-6.1-terra",
        "gpt-6-luna",
        "gpt-6-sol",
        "gpt-6.2-sol",
        "grok-4.6",
        "grok-4.7",
        "mai-code-1.1-flash",
        "mai-code-2-flash",
        "mai-code-2"
      ]
    },
    "github-cli": {
      confidence: "account-live",
      source: "GitHub Copilot CLI CAPI catalog (2026-11-24): probe helper succeeded; included models with model_picker_enabled=true and policy.state=enabled plus Auto; preserved prior research-preview/recent/local observations not returned by CAPI; removed gpt-5.6-terra, absent from the live enabled catalog.",
      models: [
        "auto",
        "observed-hydrafusion-max",
        "observed-hydrafusion",
        "observed-flint-nvfp4",
        "claude-sonnet-5.5",
        "claude-sonnet-5",
        "claude-haiku-5.5",
        "claude-haiku-4.5",
        "gpt-6.1-sol",
        "gpt-6-luna",
        "gpt-6-sol",
        "gpt-5.6-luna",
        "gpt-5.6-sol",
        "gpt-5.6-sol-fast",
        "gemini-3.8-flash",
        "gemini-4-argon",
        "mai-code-1.1-flash",
        "mai-code-2-flash",
        "mai-code-2"
      ]
    }
  }
};
