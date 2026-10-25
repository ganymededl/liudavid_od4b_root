window.MODEL_MISSION_CATALOGS = {
  updatedAt: "2026-10-24T20:44:46-04:00",
  platforms: {
    copilot: {
      confidence: "provider-level",
      source: "Microsoft Learn",
      models: [
        "microsoft-default",
        "claude-family",
        "claude-fable-5",
        "claude-mythos-5",
        "spacexai-provider"
      ]
    },
    cowork: {
      confidence: "plan-dependent",
      source: "Anthropic model catalog and Cowork documentation",
      models: [
        "claude-fable-5.1",
        "claude-opus-5.5",
        "claude-sonnet-5.5",
        "claude-haiku-5.5",
        "claude-mythos-5.1"
      ]
    },
    scout: {
      confidence: "live-exact",
      source: "Microsoft Scout m_list_models",
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
        "gpt-5.6-sol-fast",
        "gpt-6.1-sol",
        "gpt-6-luna",
        "gpt-6-sol",
        "grok-4.6",
        "grok-4.7",
        "mai-code-1.1-flash",
        "mai-code-2-flash"
      ]
    },
    "github-cli": {
      confidence: "documented-filtered",
      source: "GitHub Copilot CLI command reference",
      models: [
        "auto",
        "claude-sonnet-5.5",
        "claude-opus-5.5",
        "claude-haiku-5.5",
        "claude-haiku-4.5",
        "gpt-5.3-codex",
        "gpt-6.1-sol",
        "gpt-6-astra",
        "gpt-6-luna",
        "gemini-3.8-flash"
      ]
    }
  }
};
