"""
工具 observation 文本规范化

MCP 工具常返回 list[content block]（如 [{"type":"text","text":"https://..."}]），
直接 str() 会变成 Python 列表字面量，不利于前端识别图片 URL。
本模块统一抽出可读文本，供流式推送与历史消息格式化复用。
"""

from __future__ import annotations

import json
from typing import Any


def normalize_observation(content: Any) -> str:
    """
    将工具输出内容规范为前端/LLM 可读的纯文本。

    支持：
      - 纯字符串
      - MCP content blocks 列表（text / image / resource）
      - 其它对象 → str()
    """
    if content is None:
        return ""

    if isinstance(content, str):
        return content

    if isinstance(content, list):
        parts: list[str] = []
        for block in content:
            if isinstance(block, str):
                parts.append(block)
                continue
            if not isinstance(block, dict):
                parts.append(str(block))
                continue

            block_type = block.get("type")
            if block_type == "text" and block.get("text"):
                parts.append(str(block["text"]))
            elif block_type == "image":
                # 部分 MCP 返回 data URL 或远程 URL
                url = block.get("url") or block.get("data")
                mime = block.get("mimeType") or block.get("mime_type") or "image/png"
                if isinstance(url, str) and url.startswith("http"):
                    parts.append(url)
                elif isinstance(url, str) and url.startswith("data:"):
                    parts.append(url)
                elif isinstance(url, str):
                    parts.append(f"data:{mime};base64,{url}")
            elif block.get("text"):
                parts.append(str(block["text"]))
            elif block.get("url"):
                parts.append(str(block["url"]))
            else:
                try:
                    parts.append(json.dumps(block, ensure_ascii=False))
                except TypeError:
                    parts.append(str(block))
        return "\n".join(p for p in parts if p)

    if isinstance(content, dict):
        if content.get("type") == "text" and content.get("text"):
            return str(content["text"])
        if content.get("url"):
            return str(content["url"])
        try:
            return json.dumps(content, ensure_ascii=False)
        except TypeError:
            return str(content)

    return str(content)
