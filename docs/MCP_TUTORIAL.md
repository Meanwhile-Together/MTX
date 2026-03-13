# Model Context Protocol (MCP): Complete Tutorial

A grounded guide to MCP—what it is, how it works, and **when it’s the right fit** versus native tool calling, RAG, and other approaches that give models tools and context without any protocol.

---

## Table of Contents

1. [The landscape: giving models tools and context](#1-the-landscape-giving-models-tools-and-context)
2. [Direct / native tool calling](#2-direct--native-tool-calling)
3. [RAG and other ways to add context](#3-rag-and-other-ways-to-add-context)
4. [What MCP actually is](#4-what-mcp-actually-is)
5. [When MCP adds value (and when it doesn’t)](#5-when-mcp-adds-value-and-when-it-doesnt)
6. [The three participants: host, client, server](#6-the-three-participants-host-client-server)
7. [Where MCP servers live](#7-where-mcp-servers-live)
8. [Transports: stdio vs Streamable HTTP](#8-transports-stdio-vs-streamable-http)
9. [Implementation: protocol and primitives](#9-implementation-protocol-and-primitives)
10. [How AIs use MCP (end-to-end flow)](#10-how-ais-use-mcp-end-to-end-flow)
11. [Hugging Face and MCP](#11-hugging-face-and-mcp)
12. [Do you need to host MCP servers?](#12-do-you-need-to-host-mcp-servers)
13. [Security and trust](#13-security-and-trust)
14. [Quick reference](#14-quick-reference)

---

## 1. The landscape: giving models tools and context

LLMs get better when they can:

- **Use tools** – Call functions, APIs, or services (search, run code, query a DB, call an API).
- **Use context** – See up-to-date or private data (files, docs, DB rows) that you inject into the prompt.

**You do not need MCP to do either of these.** Most production systems today use one or more of:

- **Native tool calling** – Your app defines tools, sends their schemas to the LLM, and runs the code when the LLM asks. No protocol, no separate server.
- **RAG** – You embed documents, retrieve relevant chunks, and put them in the prompt. No MCP.
- **In-app context** – Your backend reads files, DBs, or APIs and injects the result into the prompt. Again, no MCP.

MCP is **one more option**: a **standard protocol** so that *separate* server processes can expose tools and context to *many different* AI hosts (Cursor, Claude Desktop, VS Code, etc.) in a uniform way. Its main benefit is **interoperability and composition**, not “the only way to give models tools or context.”

This tutorial covers the full picture: how tools and context work without MCP, then what MCP is and when it’s worth using.

---

## 2. Direct / native tool calling

**Direct tool calling** (often just “tool use” or “function calling”) means:

1. Your application defines a set of **tools** (name, description, input schema).
2. You send the LLM the user message **plus** these tool definitions (in the API format the provider expects).
3. The LLM can respond with either normal text or a **tool call** (tool name + arguments).
4. Your application **executes** the corresponding function (in your own code or via your own services) and passes the result back to the LLM.
5. The LLM continues the conversation with that result in context.

All of this happens **inside your stack**. No separate “tool server” or protocol.

**Examples:**

- **OpenAI** – You pass `tools` (or `functions`) to the Chat Completions API; the model returns `tool_calls`; you run the function and call the API again with `tool` messages.
- **Anthropic** – Same idea with Claude’s tool-use format: you register tools, Claude returns tool-use blocks, you execute and send back results.
- **LangChain / LlamaIndex** – You define tools (Python/JS), the framework converts them to the right API format and runs them when the model requests. Still native: your code, your process, no MCP.
- **Custom agents** – You can build the same loop in any language: define tools, call the LLM, parse tool calls, execute, repeat.

**What you get:** The model can “call” search, calculators, APIs, DB queries, file operations—whatever you implement. **Functionally this is the same as what MCP “tools” provide.** The model gets a list of callable things with schemas and returns structured calls; something executes them and feeds back results. The only difference with MCP is *who* defines the tools and *where* they run: with native tool calling, *you* define and run them in your app; with MCP, *servers* define and run them, and the host talks to those servers over a standard protocol.

So: **if you only need “my app + my tools + one LLM API,” native tool calling is enough and usually simpler.** You don’t need MCP for “models being able to run tools.”

---

## 3. RAG and other ways to add context

**RAG (retrieval-augmented generation)** gives the model extra context without any protocol:

1. You have a corpus (docs, tickets, code, etc.).
2. You chunk and embed it; store embeddings + chunks in a vector store (or use a search API).
3. For each user query, you retrieve relevant chunks (and optionally rerank).
4. You put those chunks into the prompt (system or user message).
5. The model answers using that context.

No MCP. No “resources” primitive. Just your app fetching data and editing the prompt.

**Other context patterns:**

- **Read files in your backend** – User asks “what’s in my config?”; your server reads the file and injects it into the prompt.
- **Query a DB** – Your code runs a query and adds the result to the prompt.
- **Call an API** – Your code calls a third-party API and gives the response to the model.

Again, all of this is **native**: your code, your process. The model gets context because **you** put it in the prompt. MCP “resources” are another way to do that—a server exposes named resources, and the host fetches them via the protocol and injects them. So **RAG and in-app context are real alternatives.** Use them when you have one app, one pipeline, and no need for “the same context source in Cursor, Claude Desktop, and VS Code.”

---

## 4. What MCP actually is

**Model Context Protocol (MCP)** is an **open specification** that defines:

- How an **MCP client** (inside an AI application) discovers and calls **tools**, reads **resources**, and uses **prompts** from an **MCP server**.
- Message format (JSON-RPC 2.0), lifecycle (initialize, capabilities), and transports (stdio, Streamable HTTP).

So MCP is **not**:

- A product or a cloud.
- The only way to give models tools or context.
- Required for tool calling or RAG.

It **is**:

- A **protocol** so that a *server process* (possibly from a third party or the ecosystem) can expose tools/resources/prompts in a **standard way**, and a *host* (Cursor, Claude Desktop, VS Code, Zed, etc.) can connect to many such servers **without baking each integration into the host**.

Rough analogy: **LSP** standardizes how editors talk to language servers so one language server works in many editors. **MCP** standardizes how AI hosts talk to “context/tool servers” so one MCP server works in many hosts, and one host can use many MCP servers via config.

---

## 5. When MCP adds value (and when it doesn’t)

**MCP is useful when:**

- You want **the same integration in multiple hosts** – e.g. “Hugging Face Hub search” or “my internal tool server” available in Cursor, Claude Desktop, and VS Code without each app implementing a custom plugin.
- You want to **add capabilities by configuration** – users (or admins) add an MCP server in settings; the host gets new tools/resources without a host code change.
- You’re **building a server** that you want others to use in *their* choice of host – one implementation, many clients.
- You’re in an **ecosystem** where many MCP servers already exist (filesystem, Hub, Sentry, etc.) and you want to reuse them.

**You can skip MCP when:**

- You’re building **one application** with **your own tools** – native tool calling (OpenAI, Anthropic, LangChain, etc.) is simpler and sufficient.
- You only need **RAG or in-app context** – no need for MCP resources.
- You don’t care about **cross-host reuse** – a single custom integration is fine.

**Summary:** MCP solves **interoperability and composition** (same server, many hosts; many servers, one host). It does **not** solve “how do we give models tools or context?”—that’s already solved by native tool calling and RAG. Use MCP when the interop/composition story is worth the extra moving parts.

---

## 6. The three participants: host, client, server

When you *do* use MCP, the architecture looks like this:

```
┌─────────────────────────────────────────────────────────────┐
│  MCP HOST (e.g. Cursor, Claude Desktop, VS Code)            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ MCP Client 1│  │ MCP Client 2│  │ MCP Client 3│  ...      │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘          │
└─────────┼────────────────┼────────────────┼──────────────────┘
          │                │                │
          ▼                ▼                ▼
   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
   │ MCP Server A │ │ MCP Server B │ │ MCP Server C │
   └──────────────┘ └──────────────┘ └──────────────┘
```

- **MCP Host** – The AI application. It creates one **MCP client** per configured server, aggregates tools/resources, and drives the LLM loop (including passing tool results back).
- **MCP Client** – Lives inside the host. Holds a single connection to one MCP server; sends JSON-RPC (e.g. `tools/list`, `tools/call`, `resources/read`) and forwards responses.
- **MCP Server** – Separate process or service. Exposes **tools**, **resources**, and/or **prompts** according to the MCP spec.

So: **Host** uses **clients** to talk to **servers**. The host never runs your tool code; it asks the server to run it via the protocol.

---

## 7. Where MCP servers live

- **Local (stdio)** – The host **spawns** the server as a subprocess on the same machine. Communication is stdin/stdout. One process per connection. Typical for filesystem, DB, or CLI-style servers. Config is usually a command + args.
- **Remote (Streamable HTTP)** – The server runs somewhere on the network (your infra, Cloud Run, Azure, or a vendor). The host connects via HTTP (POST + optional SSE). One server can serve many clients. Config is URL + auth (e.g. API key, bearer token).

You don’t “install MCP” in one place. You install or run a **host** (e.g. Cursor); the host starts or connects to **servers** based on config.

---

## 8. Transports: stdio vs Streamable HTTP

| Aspect | stdio | Streamable HTTP |
|--------|--------|-------------------|
| Where server runs | Local | Remote |
| How | Subprocess; stdin/stdout | HTTP POST (+ SSE for streaming) |
| Clients per server | One | Many |
| Auth | N/A (local) | Bearer, API key, OAuth, etc. |

The **data layer** (JSON-RPC, tools, resources, prompts) is the same; only the transport differs. SSE-only is deprecated in favor of Streamable HTTP for new remote servers.

---

## 9. Implementation: protocol and primitives

- **Base:** JSON-RPC 2.0, stateful connection, lifecycle (`initialize` + capability negotiation).
- **Server primitives:**
  - **Tools** – `tools/list`, `tools/call` (name + arguments).
  - **Resources** – `resources/list`, `resources/read` (e.g. by URI).
  - **Prompts** – `prompts/list`, `prompts/get` (templates with arguments).
- **Client primitives (optional):** logging, elicitation (ask user for input), sampling (server asks host to run the LLM).

SDKs (Python, TypeScript, etc.) handle the protocol; you implement handlers for your tools/resources/prompts.

---

## 10. How AIs use MCP (end-to-end flow)

Conceptually the same as native tool calling; the difference is where tools come from and where they run:

1. Host starts or connects to MCP servers; each connection has a client.
2. Host calls `tools/list` (and optionally `resources/list`, `prompts/list`) and builds a unified registry.
3. User sends a message. Host gives the LLM the message plus the list of tools (and any resources/prompts it injects).
4. LLM may return a tool call (name + arguments). Host maps it to an MCP server and sends `tools/call` via the right client.
5. Server runs the tool and returns content. Host feeds that back to the LLM.
6. LLM continues (text or another tool call).

So: the **model** never talks to MCP. The **host** does. The host gets tool definitions and results over the wire from MCP servers instead of from in-app code.

---

## 11. Hugging Face and MCP

**Does Hugging Face support MCP?** Yes.

- **Hugging Face MCP Server** – Hosted by HF. Connects your MCP-capable assistant (Cursor, VS Code, Claude Desktop, etc.) to the Hub: search models, datasets, Spaces, papers; run community tools via MCP-compatible Gradio Spaces. You add it in your client config ([https://huggingface.co/settings/mcp](https://huggingface.co/settings/mcp)); you don’t host it.
- **transformers.js** – Runs models (including from the Hub) in the browser or Node. It is **not** an MCP server or client; it’s model execution. MCP is about the *assistant* using the Hub (search, tools); transformers.js is about *running* models.
- **Client libraries** – `@huggingface/mcp-client` (JS) and `huggingface_hub.MCPClient` (Python) let you build agents that connect to MCP servers; they don’t replace Cursor/Claude as hosts.

---

## 12. Do you need to host MCP servers?

**No**, for many use cases. You can use only:

- Hosted servers (e.g. Hugging Face, Sentry), or  
- Local servers (host starts them via stdio),

and just configure your client. You only **host** an MCP server when you need a central or multi-tenant endpoint (e.g. your own product or internal service).

---

## 13. Security and trust

MCP exposes **tools** (arbitrary execution) and **resources** (data). The spec recommends user consent, data privacy, and tool safety; **hosts** are expected to enforce approval and scoping. When you add an MCP server, you’re trusting it with whatever capabilities it declares—same trust model as installing a plugin or using a third-party API.

---

## 14. Quick reference

| Topic | Answer |
|-------|--------|
| **What is MCP?** | Open protocol for *hosts* to get tools/resources/prompts from *servers* in a standard way. |
| **Do I need MCP for tool calling?** | No. Native tool calling (OpenAI, Anthropic, LangChain, etc.) gives the same capability. |
| **Do I need MCP for context?** | No. RAG and in-app context (files, DB, API) work without MCP. |
| **When is MCP worth it?** | When you want the same integration in many hosts, or many servers in one host, without custom code per integration. |
| **What do servers expose?** | Tools (callable), resources (read-only), prompts (templates). |
| **Where do servers run?** | Local (stdio, host spawns) or remote (Streamable HTTP). |
| **How is it implemented?** | JSON-RPC 2.0, lifecycle, stdio or Streamable HTTP. SDKs in Python, TypeScript, etc. |
| **Hugging Face?** | HF MCP Server for Hub + Spaces; transformers.js is separate (model execution). |
| **Hosting?** | Optional; use existing or local servers unless you need a central/shared endpoint. |

---

## Where to go next

- **MCP spec and docs:** [modelcontextprotocol.io](https://modelcontextprotocol.io/)
- **Reference servers:** [github.com/modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers)
- **Hugging Face MCP:** [huggingface.co/settings/mcp](https://huggingface.co/settings/mcp), [Hugging Face MCP Server docs](https://huggingface.co/docs/hub/en/hf-mcp-server)

Use this to decide **when** MCP is the right fit (interop, composition, ecosystem) and **when** to stick with native tool calling or RAG—then use MCP only where it pays off.
