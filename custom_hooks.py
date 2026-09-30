# LiteLLM custom hooks for Claude Desktop -> Experiential Labs
#
# Jugaad #1 — PDF "document" blocks ko text mein convert karta hai.
#   Claude Desktop jab PDF attach karta hai to Anthropic API ka `document` block
#   bhejta hai. Free models (gpt-6-luna, deepseek, mimo) PDF document input
#   support NAHI karte. Yeh hook base64 PDF se text nikaal kar usay normal
#   `text` block bana deta hai -> har free text model PDF parh leta hai.
#
# Jugaad #2 — max_tokens ka minimum 16 (gateway requirement). Desktop app ke
#   health probes max_tokens=1 bhejte hain, isse 400 aata tha.
#
# Jugaad #3 — image blocks ke liye model auto-switch. Experiential Labs ke
#   free text-only models (MiMo, DeepSeek) image input par 400 dete hain.
#   Yeh hook image block dekhte hi request ko vision-capable route
#   (gpt-6-luna) par shift kar deta hai -> "pic" wale messages bhi padh jate hain.
#
# Jugaad #3b — URL-type images (`source.type == "url"`) ko locally download
#   karke base64 mein badal deta hai. Kai image-host providers ke server-side
#   fetcher ko block karte hain (403/404); local fetch aam tor par chal jata hai.
#   Download fail ho to original URL block hi rehne deta hai.

import base64
import io
import logging
from typing import Any, Optional

from litellm.integrations.custom_logger import CustomLogger

logger = logging.getLogger("claude_jugaad")

MIN_MAX_TOKENS = 16

# Image input nahi le sake wale routes (test kiya gaya: 400 invalid_request)
IMAGE_BAD_MODELS = {
    "claude-pro-2-6",        # mimo-v2.6-pro
    "claude-flash-free",     # deepseek-v4-flash
    "mimo-v2.6-pro",
    "deepseek-v4-flash",
    "or-free",               # OR free group: image-capable entries nahi
}
# Vision-capable jahan image aate hi shift karna hai
IMAGE_ROUTE_TARGET = "claude-sonnet-4-5-20250929"  # -> gpt-6-luna (images OK)


def _has_image_block(content: Any) -> bool:
    if isinstance(content, str):
        return False
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict):
                if block.get("type") == "image":
                    return True
                if block.get("type") == "tool_result":
                    if _has_image_block(block.get("content")):
                        return True
    return False


def _extract_pdf_text(raw: bytes) -> str:
    import pypdf

    reader = pypdf.PdfReader(io.BytesIO(raw))
    parts = []
    for i, page in enumerate(reader.pages):
        try:
            text = page.extract_text() or ""
        except Exception as exc:  # noqa: BLE001
            text = ""
            logger.warning("PDF page %s extract failed: %s", i + 1, exc)
        if text.strip():
            parts.append(f"--- Page {i + 1} ---\n{text}")
    return "\n\n".join(parts)


def _download(url: str) -> bytes:
    import urllib.request

    req = urllib.request.Request(url, headers={"User-Agent": "litellm-doc-hook"})
    with urllib.request.urlopen(req, timeout=30) as resp:  # noqa: S310
        return resp.read()


def _convert_document_block(block: dict) -> dict:
    source = block.get("source") or {}
    src_type = source.get("type")
    media_type = source.get("media_type", "")
    title = block.get("title") or ""
    text: Optional[str] = None

    try:
        if src_type == "base64" and media_type == "application/pdf":
            text = _extract_pdf_text(base64.b64decode(source.get("data", "")))
        elif src_type == "base64" and media_type.startswith("text/"):
            text = base64.b64decode(source.get("data", "")).decode("utf-8", "replace")
        elif src_type == "text":
            text = source.get("data", "")
        elif src_type == "url":
            raw = _download(source.get("url", ""))
            if media_type == "application/pdf" or raw[:4] == b"%PDF":
                text = _extract_pdf_text(raw)
            else:
                text = raw.decode("utf-8", "replace")
    except Exception as exc:  # noqa: BLE001
        logger.warning("document conversion failed (%s)", exc)
        text = None

    if text is None:
        text = "[attached document could not be converted to text]"

    header = f"[Attached document{': ' + title if title else ''} — extracted text]\n"
    return {"type": "text", "text": header + text}


def _sniff_image_mime(raw: bytes) -> Optional[str]:
    if raw[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if raw[:2] == b"\xff\xd8":
        return "image/jpeg"
    if raw[:6] in (b"GIF87a", b"GIF89a"):
        return "image/gif"
    if raw[:4] == b"RIFF" and raw[8:12] == b"WEBP":
        return "image/webp"
    return None


def _convert_block(block: Any) -> Any:
    if not isinstance(block, dict):
        return block

    btype = block.get("type")
    if btype == "document":
        return _convert_document_block(block)

    if btype == "image":
        source = block.get("source") or {}
        if source.get("type") == "url":
            try:
                raw = _download(source.get("url", ""))
                mime = _sniff_image_mime(raw)
                if mime:
                    return {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": mime,
                            "data": base64.b64encode(raw).decode("ascii"),
                        },
                    }
            except Exception as exc:  # noqa: BLE001
                logger.warning("url image download failed (%s)", exc)
        return block

    if btype == "tool_result":
        content = block.get("content")
        if isinstance(content, list):
            block = dict(block)
            block["content"] = [_convert_block(b) for b in content]
        return block

    return block


def _convert_content(content: Any) -> Any:
    if isinstance(content, list):
        return [_convert_block(b) for b in content]
    return content


class ClaudeJugaadHook(CustomLogger):
    async def async_pre_call_hook(
        self,
        user_api_key_dict,
        cache,
        data: dict,
        call_type: str,
    ) -> Optional[dict]:
        try:
            if not isinstance(data, dict):
                return data

            mt = data.get("max_tokens")
            if isinstance(mt, int) and 0 <= mt < MIN_MAX_TOKENS:
                data["max_tokens"] = MIN_MAX_TOKENS
            mtt = data.get("max_completion_tokens")
            if isinstance(mtt, int) and 0 <= mtt < MIN_MAX_TOKENS:
                data["max_completion_tokens"] = MIN_MAX_TOKENS

            messages = data.get("messages")
            if isinstance(messages, list):
                for msg in messages:
                    if isinstance(msg, dict) and "content" in msg:
                        msg["content"] = _convert_content(msg["content"])

                # Jugaad #3: image present ho to text-only route ko vision par shift
                model = data.get("model")
                if isinstance(model, str) and model in IMAGE_BAD_MODELS:
                    has_image = _has_image_block(data.get("system")) or any(
                        isinstance(m, dict) and _has_image_block(m.get("content"))
                        for m in messages
                    )
                    if has_image:
                        logger.info(
                            "image request on %s -> switching to %s",
                            model,
                            IMAGE_ROUTE_TARGET,
                        )
                        data["model"] = IMAGE_ROUTE_TARGET

            system = data.get("system")
            if isinstance(system, list):
                data["system"] = _convert_content(system)
        except Exception as exc:  # noqa: BLE001
            logger.warning("ClaudeJugaadHook failed: %s", exc)

        return data


proxy_handler_instance = ClaudeJugaadHook()