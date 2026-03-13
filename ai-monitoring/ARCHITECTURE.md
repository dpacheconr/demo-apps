# AIM Demo — Architecture Diagram

## High-Level Overview

```mermaid
graph LR
    User(["👤 User"])
    Locust(["🔁 Load Generator"])

    User --> UI["🖥️ Flask UI"]
    Locust --> Agent

    UI <--> Agent["🤖 AI Agent"]
    Agent <-->|"reason"| ModelA["🧠 Model A"]
    Agent <-->|"reason"| ModelB["🧠 Model B"]
    Agent <-->|"tools"| MCP["⚙️ MCP Server"]

    UI -. " " .-> NR["📊 New Relic"]
    Agent -. " " .-> NR
    MCP -. " " .-> NR

    classDef user      fill:#4A90D9,stroke:#2C5F8A,color:#fff
    classDef ui        fill:#7B68EE,stroke:#5A4DB5,color:#fff
    classDef agent     fill:#E8734A,stroke:#C4522A,color:#fff
    classDef model     fill:#5BAD8F,stroke:#3D8A6E,color:#fff
    classDef mcp       fill:#F0A500,stroke:#C47E00,color:#fff
    classDef nr        fill:#1CE783,stroke:#0FB863,color:#1a1a1a
    classDef load      fill:#9B9B9B,stroke:#6B6B6B,color:#fff

    class User user
    class Locust load
    class UI ui
    class Agent agent
    class ModelA,ModelB model
    class MCP mcp
    class NR nr
```

---

## Service Overview

| Service | Port | Technology | Role |
|---|---|---|---|
| **flask-ui** | 8501 | Flask 3.0 + gunicorn | Web UI (Home, Tools, Chat, Debug) |
| **ai-agent** | 8001 | LangChain + FastAPI | Reasoning engine with tool calling |
| **mcp-server** | 8002 | FastMCP + FastAPI | Mock system operation tools (6 tools) |
| **ollama-model-a** | 11434 | Ollama · mistral:7b-instruct-v0.3 | LLM Model A (~4 GB) |
| **ollama-model-b** | 11435 | Ollama · ministral-3:8b q8_0 | LLM Model B (~8 GB) |
| **locust** | 8089 | Locust 2.43.0 | Passive load generator (5–10 req/hr) |

---

## Architecture Diagram

```mermaid
graph TD
    User(["👤 User<br/>(Browser)"])
    User -->|"HTTP :8501"| FlaskUI

    Locust -->|"HTTP :8001<br/>passive load · 5–10 req/hr"| AIAgent

    subgraph Docker["aim-network  (Docker bridge)"]
        FlaskUI["flask-ui  :8501<br/>Flask + gunicorn<br/>─────────────<br/>NR APM + Browser RUM"]

        FlaskUI -->|"HTTP REST :8001<br/>/tools · /chat"| AIAgent
        FlaskUI -->|"HTTP :8002<br/>/debug (direct)"| MCPServer

        AIAgent["ai-agent  :8001<br/>LangChain + FastAPI<br/>─────────────<br/>NR APM + AI Monitoring"]

        AIAgent -->|"OpenAI-compat API<br/>:11434"| ModelA
        AIAgent -->|"OpenAI-compat API<br/>:11435"| ModelB
        AIAgent -->|"MCP Protocol (HTTP)<br/>:8002"| MCPServer

        MCPServer["mcp-server  :8002<br/>FastMCP + FastAPI<br/>─────────────<br/>NR APM"]

        ModelA["ollama-model-a  :11434<br/>mistral:7b-instruct-v0.3<br/>~4 GB · reliable JSON"]
        ModelB["ollama-model-b  :11435<br/>ministral-3:8b q8_0<br/>~8 GB · 8-bit quant"]

        Locust["locust  :8089<br/>Passive load gen<br/>18-prompt pool<br/>50/50 model split"]
    end

    subgraph NR["New Relic"]
        NRCloud["New Relic One<br/>─────────────<br/>APM · AI Monitoring<br/>Distributed Tracing<br/>Browser RUM (flask-ui)<br/>LLM Feedback Events"]
    end

    FlaskUI -. "telemetry<br/>(APM + RUM)" .-> NRCloud
    AIAgent -. "telemetry<br/>(APM + LLM metrics<br/>token usage · feedback)" .-> NRCloud
    MCPServer -. "telemetry<br/>(APM + traces)" .-> NRCloud
```

---

## Distributed Trace Flow

```
Browser (RUM)
  └─► flask-ui  (NR Python Agent · W3C trace context)
        └─► ai-agent  (NR Python Agent · AI Monitoring)
              ├─► ollama-model-a / ollama-model-b  (LLM call)
              └─► mcp-server  (NR Python Agent · tool invocations)
```

---

## Key Interactions

| From | To | Protocol | Purpose |
|---|---|---|---|
| User | flask-ui | HTTP | Web interface |
| flask-ui | ai-agent | HTTP REST | Tool workflows + chat |
| flask-ui | mcp-server | HTTP | Debug page (direct tool testing) |
| ai-agent | ollama-model-a/b | OpenAI-compat HTTP | LLM inference (A/B model selection) |
| ai-agent | mcp-server | MCP over HTTP | Tool execution (6 mock system ops) |
| locust | ai-agent | HTTP | Background load, 5–10 req/hr |
| flask-ui / ai-agent / mcp-server | New Relic | HTTPS | APM telemetry + AI metrics |
