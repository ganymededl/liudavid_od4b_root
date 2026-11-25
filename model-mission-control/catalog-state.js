window.MODEL_MISSION_CATALOGS = {
  updatedAt: "2026-11-25T06:35:00-05:00",
  platforms: {
    copilot: {
      confidence: "account-observed",
      source: "Authenticated Microsoft 365 Copilot Chat picker captured (2026-11-25); current top-level modes: Auto=Magic, Quick response=Chat, Think deeper=Reasoning, Advanced reasoning=DeepWork, Grok 4.6=Grok_Reasoning, Claude, MAI=Mai_Auto, GPT, Model fusion. Claude submenu: Sonnet 5.5=Claude_Sonnet, Opus 5.5=Claude_Opus, Fable 5.1=Claude_Fable. GPT submenu: GPT-6=Gpt_6_Sol_Chat, GPT-6.2 Sol=Gpt_62_Sol_Reasoning, GPT-6.2 Astra=Gpt_62_Astra_Reasoning; GPT-5.6 Sol choices previously listed are no longer visible. Model fusion Compare=Forum and Critique=Enhance are not model choices.",
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
        "Gpt_6_Sol_Chat",
        "Gpt_62_Sol_Reasoning",
        "Gpt_62_Astra_Reasoning"
      ]
    },
    cowork: {
      confidence: "account-observed",
      source: "Authenticated Microsoft 365 Copilot Cowork model picker captured (2026-11-25): Auto and Fast; Claude submenu: Opus 5.5, Opus 5.5 Fast, Sonnet 5.5; GPT submenu: GPT 6.2 Astra, GPT 6.2 Sol, GPT 6.2 Sol Fast. Picker exposed labels but not state IDs; retained the existing exact IDs after matching visible choices. No Anthropic/API source used.",
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
      source: "Microsoft Scout m_list_models (2026-11-25)",
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
      source: "GitHub Copilot CLI CAPI catalog (2026-11-25): probe helper succeeded; included models with model_picker_enabled=true and policy.state=enabled plus Auto; preserved observed-hydrafusion-max, observed-hydrafusion, observed-flint-nvfp4; no fresh New/Removed entries. gpt-5.6-terra remains absent from the live enabled catalog.",
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
