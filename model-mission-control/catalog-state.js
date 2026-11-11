window.MODEL_MISSION_CATALOGS = {
  updatedAt: "2026-11-11T06:32:21-05:00",
  platforms: {
    copilot: {
      confidence: "account-observed",
      source: "Last successful authenticated Microsoft 365 Copilot Chat picker capture (2026-11-10): Auto, Quick response, Think deeper, Grok 4.6, Model fusion (Critique); Claude: Sonnet 5, Sonnet 5.5, Opus 5.5; GPT: GPT-5.6 Sol Quick response, GPT-6, GPT-5.6 Sol Think deeper, GPT-6.1 Sol. GPT-6 Astra and Advanced reasoning (Experimental) not visible in the picker capture. Exact IDs unavailable for Grok/Model fusion. 2026-11-11 refresh probe failed at sign-in; retained last-known state.",
      models: [
        "copilot-auto",
        "copilot-quick-response",
        "copilot-think-deeper",
        "claude-sonnet-5",
        "claude-sonnet-5.5",
        "claude-opus-5.5",
        "gpt-5.6-sol-quick",
        "gpt-6",
        "gpt-5.6-sol-think",
        "gpt-6.1-sol"
      ]
    },
    cowork: {
      confidence: "account-observed",
      source: "Last successful authenticated Microsoft 365 Copilot Cowork picker capture (2026-11-10): Auto; GPT: GPT 6.1 Sol, GPT 6 Astra, GPT 5.5; Claude: Opus 5.5, Sonnet 5.5, Fable 5.2. Exact picker state IDs were not exposed; retained cowork-managed. 2026-11-11 refresh probe failed at sign-in; retained last-known state.",
      models: [
        "cowork-managed"
      ]
    },
    scout: {
      confidence: "live-exact",
      source: "Microsoft Scout m_list_models (2026-11-11)",
      models: [
        "auto",
        "claude-sonnet-5",
        "claude-haiku-4.5",
        "gpt-5.6-sol",
        "gpt-5.6-terra",
        "gpt-5.6-luna",
        "gpt-5.3-codex",
        "claude-haiku-5.5",
        "claude-sonnet-5.5",
        "gemini-3.8-flash",
        "gemini-4-argon",
        "gemini-4-carbon",
        "gpt-5.6-sol-fast",
        "gpt-6.1-sol",
        "gpt-6.1-terra",
        "gpt-6-luna",
        "gpt-6-sol",
        "grok-4.6",
        "grok-4.7",
        "mai-code-1.1-flash"
      ]
    },
    "github-cli": {
      confidence: "account-live",
      source: "GitHub Copilot CLI CAPI catalog (2026-11-11): helper succeeded; included models with model_picker_enabled=true and policy.state=enabled, added Auto; preserved prior research-preview/recent/local observations not returned by CAPI",
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
        "gpt-5.6-terra",
        "gemini-3.8-flash",
        "gemini-4-argon",
        "mai-code-1.1-flash"
      ]
    }
  }
};
