# 言栖 · 智能聊天机器人

基于 **LangChain + LangGraph + FastAPI + Vue 3** 的智能聊天机器人，支持 SSE 流式输出、动态工具选择、多轮会话记忆与 Human-in-the-Loop 工具审批。

## 功能特性

- **流式对话**：逐 token 实时推送，打字机效果呈现回答
- **工具调用**：前端可按需勾选启用/禁用的工具，支持内置工具 + MCP 外部工具
- **人工审批（HITL）**：敏感工具需用户审批后执行，支持批准 / 编辑 / 拒绝 / 自行回复
- **多轮会话记忆**：双层存储（会话元数据 + 对话状态），支持 InMemory / MySQL
- **会话顶置**：重要会话可顶置到列表顶部
- **消息删除与回退**：支持级联删除与回填输入框重新编辑
- **页面配置大模型**：设置面板修改 API 地址、密钥和模型名称，保存后热重载
- **对话压缩**：长对话超过 token 阈值时自动摘要压缩，可配置

## 项目结构

```
yanqi/
├── yanqi.sh                         # 一键启动/停止/重启（macOS / Linux）
├── yanqi.ps1                        # 一键启动/停止/重启（Windows）
├── mcp_workspace/                   # filesystem MCP 沙箱目录
├── log/                             # 运行日志
├── back/                            # 后端（Python + FastAPI + LangChain + LangGraph）
│   ├── main.py                      # FastAPI 入口
│   ├── config.py                    # 配置管理
│   ├── .env                         # 环境变量（勿提交）
│   ├── mcp_servers.json             # MCP 工具配置（真实服务）
│   ├── mcp_servers.example.json     # MCP 配置模板
│   ├── agent/                       # Agent 编排（core / stream / interrupt / graph）
│   ├── tools/                       # 内置工具 + MCP 加载
│   ├── middleware/                  # 摘要等中间件
│   ├── conversation/                # 会话元数据存储
│   ├── checkpoint/                  # 对话状态存储
│   ├── entity/                      # Pydantic 模型
│   ├── services/                    # 配置服务
│   ├── routers/                     # API 路由
│   └── requirements.txt
└── front/                           # 前端（Vue 3 + Vite）
    └── src/
        ├── views/ChatView.vue
        ├── components/              # 消息、会话列表、工具、审批、设置
        └── api/                     # REST + SSE
```

## 技术栈

| 层面 | 技术 | 说明 |
|------|------|------|
| 后端 | FastAPI | 异步 Web API |
| AI | LangChain / LangGraph | LLM 调用、ReAct、checkpointer、HITL |
| LLM | OpenAI 兼容 | DeepSeek / 智谱 / Moonshot / OpenAI 等 |
| 流式 | SSE | 逐 token 输出 |
| 前端 | Vue 3 + Vite | Composition API |

## 快速启动

### 前置条件

- **Python ≥ 3.10**
- Node.js（前端开发服务器）

### 配置

```bash
cd back
cp .env.example .env
# 编辑 .env，填入 API_KEY
```

### 首次准备（仅一次）

```powershell
# Windows
cd back
python -m venv venv
.\venv\Scripts\activate
pip install -r requirements.txt
```

```bash
# macOS / Linux
cd back
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Windows（推荐脚本）

在项目根目录 PowerShell 中执行：

```powershell
.\yanqi.ps1 start
.\yanqi.ps1 stop
.\yanqi.ps1 restart
.\yanqi.ps1 status
```

也可只操作一端：`.\yanqi.ps1 start backend` / `.\yanqi.ps1 start frontend`

若执行策略受限，可先：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

### macOS / Linux（脚本）

```bash
chmod +x yanqi.sh
./yanqi.sh start
```

| 命令 | 说明 |
|------|------|
| `./yanqi.sh start` / `.\yanqi.ps1 start` | 启动前后端 |
| `stop` / `restart` / `status` | 停止 / 重启 / 状态与健康检查 |

### 手动启动（不使用脚本）

```powershell
# 后端
cd back
.\venv\Scripts\activate
python main.py

# 另开终端：前端
cd front
npm install   # 仅首次
npm run dev
```

### 服务地址

| 服务 | 地址 |
|------|------|
| 前端 | http://localhost:5173 |
| 后端 | http://localhost:8001 |
| API 文档 | http://localhost:8001/docs |
| 健康检查 | http://localhost:8001/api/health |

## 环境变量（节选）

在 `back/.env` 中配置（也可通过前端设置面板修改部分项）：

| 变量 | 说明 | 默认 |
|------|------|------|
| `API_KEY` | LLM API 密钥 | — |
| `BASE_URL` | API 基础地址 | `https://api.deepseek.com` |
| `MODEL_NAME` | 模型名称 | `deepseek-v4-flash` |
| `CONVERSATION_BACKEND` | 会话元数据：`memory` / `mysql` | `memory` |
| `CHECKPOINT_BACKEND` | 对话状态：`memory` / `mysql` | `memory` |
| `MYSQL_DATABASE` | MySQL 库名 | `yanqi` |

完整说明见 `back/.env.example`。

## 内置工具

| 工具 | 说明 | 默认需审批 |
|------|------|------------|
| `get_datetime` | 查询当前日期时间 | 否 |
| `get_weather` | 查询城市实时天气（Open-Meteo） | 否 |

### MCP 外部工具（已接入示例）

项目默认通过 `back/mcp_servers.json` 加载两个真实 MCP 服务（Windows 用 `cmd /c npx`）：

| 服务器 | 包名 | 作用 |
|--------|------|------|
| `filesystem` | `@modelcontextprotocol/server-filesystem` | 读写 `mcp_workspace/` 沙箱目录 |
| `memory` | `@modelcontextprotocol/server-memory` | 知识图谱记忆（实体/关系） |
| `chart` | `@antv/mcp-server-chart` | 生成柱状图/折线图/饼图等可视化图表（返回图片） |

- 沙箱目录：项目根下 `mcp_workspace/`（可放文本供对话读取）
- MCP 工具默认需要人工审批（HITL）
- 修改配置后可调用 `POST /api/tools/reload` 热重载，或重启后端
- macOS / Linux 可将 `command` 改为 `npx`，并去掉 args 里的 `/c`、`npx` 两项（参考官方文档）

## 协议

MIT（见 `LICENSE`）
