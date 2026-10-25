window.MODEL_MISSION_AI = Object.freeze({
  enabled: true,
  tenantId: "6d5898fd-dcaf-43c3-b0ea-f9be4a9da1a5",
  clientId: "597be53b-a64b-4759-8469-34379db497d8",
  scope: "api://2d2b1294-b9d7-4cd0-aa96-2b615cc0a7fb/access_as_user",
  apiUrl: "https://func-model-mission-control-eecd0085.azurewebsites.net/api/recommend",
  redirectUri: window.location.hostname === "localhost"
    ? "http://localhost:8765/model-mission-control/"
    : "https://ganymededl.github.io/liudavid_od4b_root/model-mission-control/"
});
