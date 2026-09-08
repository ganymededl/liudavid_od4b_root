New: https://ganymededl.github.io/nypd_copilotdemo/
Old: https://witty-moss-065485610.7.azurestaticapps.net/

NYPD Copilot Demo
An interactive demo site that shows how Microsoft Copilot Chat can support realistic NYPD workflows using role-based prompt examples. The app is a single-page HTML experience designed for live demos, internal presentations, and stakeholder conversations around Copilot Chat in GCC environments.

Overview
This project presents practical, ready-to-use Copilot Chat prompts for four NYPD-facing roles:

Police Officer Sector

Desk Officer / Platoon Commander

Integrity Control / Operations Lieutenant

Precinct Detective

Each role includes three scenario-based prompts, plus plain-language explanations of:

What the prompt does

What good output should look like

Where Copilot Chat helps most

What remains out of scope with a basic Copilot Chat license

The experience is optimized for a polished demo setting, with interactive role cards, copy-to-clipboard prompt actions, NYPD visual mode, background media, and a clear explanation of licensing boundaries.

Features
Role-based prompt explorer for four NYPD user personas

Three practical prompts per role

Copy-to-clipboard support for each prompt

Guidance on expected output quality

Section explaining what Copilot Chat will and will not do with the basic license

NYPD-themed visual mode toggle

Ambient background video and optional audio controls

Mobile-responsive single-page layout

Live demo call-to-action for scheduling a walkthrough

Use Cases Covered
Police Officer Sector
Activity Log narrative cleanup

Plain-English statute explanation

Respectful community talking points

Desk Officer / Platoon Commander
Roll call drafting

Mutual aid request drafting

End-of-tour recap generation

Integrity Control / Operations Lieutenant
Interim Order summarization

CompStat talking points

FOIL response drafting

Precinct Detective
Witness interview preparation

Case chronology generation for ADA review

Follow-up report rewriting

Tech Stack
This repo is intentionally lightweight and easy to deploy.

HTML5

CSS3

Vanilla JavaScript

Azure-hosted media assets

Azure Static Web Apps compatible structure

Project Structure
text
.
├── .github/
├── README.md
├── index.html
└── staticwebapp.config.json
Deployment
This project is suitable for static hosting platforms such as Azure Static Web Apps. The current repo structure suggests a simple static deployment with no build step required.

Run locally
Because this is a static site, you can run it locally by opening index.html in a browser, or by serving the folder with a lightweight local web server.

Example:

bash
python -m http.server 8000
Then open http://localhost:8000.

Design Notes
The interface is designed to make Copilot Chat value concrete for operational users and leadership audiences. Rather than discussing AI capabilities abstractly, it demonstrates high-confidence internal writing and summarization scenarios that fit normal supervisory review workflows.

It also clearly separates helpful use cases from excluded ones, including system limitations, governance boundaries, and human-review requirements.

Intended Audience
This demo is useful for:

NYPD leadership and command staff

IT and digital transformation teams

Microsoft sellers or solution specialists

Internal champions evaluating Copilot Chat adoption

Stakeholders who need practical examples instead of generic AI messaging

Notes
This repo focuses on prompt examples and presentation, not backend integrations.

The examples are scoped around Copilot Chat with Enterprise Data Protection in GCC.

Outputs shown in the app are intended for review workflows, not direct unsupervised external use.

Future Enhancements
Potential next steps for the project:

Add more NYPD roles or bureaus

Include tenant-specific prompts and policies

Add analytics for prompt engagement

Package the app with reusable branding/config options

Add a simple admin JSON model for maintaining prompts without editing HTML

License
Add the license that matches how you want to share or reuse this repository.
