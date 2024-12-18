"""
内置工具集

使用 LangChain 的 @tool 装饰器定义工具，框架会自动：
  - 根据函数签名生成参数 JSON Schema
  - 根据 docstring 生成工具描述
  - 封装为 BaseTool 实例，可被 Agent 的 bind_tools() 使用

当前内置 2 个工具：
  - get_datetime: 获取当前日期时间（支持时区）
  - get_weather:  查询城市天气（Open-Meteo，无需 API Key）
"""

import json
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone, timedelta

from langchain.tools import tool


# WMO Weather interpretation codes → 中文简述
# https://open-meteo.com/en/docs
_WMO_WEATHER = {
    0: "晴朗",
    1: "大体晴朗",
    2: "局部多云",
    3: "阴天",
    45: "有雾",
    48: "沉积霜雾",
    51: "小毛毛雨",
    53: "中毛毛雨",
    55: "大毛毛雨",
    56: "冻毛毛雨（轻）",
    57: "冻毛毛雨（重）",
    61: "小雨",
    63: "中雨",
    65: "大雨",
    66: "冻雨（轻）",
    67: "冻雨（重）",
    71: "小雪",
    73: "中雪",
    75: "大雪",
    77: "雪粒",
    80: "小阵雨",
    81: "中阵雨",
    82: "大阵雨",
    85: "小阵雪",
    86: "大阵雪",
    95: "雷暴",
    96: "雷暴伴小冰雹",
    99: "雷暴伴大冰雹",
}


def _http_get_json(url: str, timeout: float = 10.0) -> dict:
    """发起 GET 请求并解析 JSON（标准库，无额外依赖）。"""
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "YanqiAgent/1.0", "Accept": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


@tool
def get_datetime(timezone_offset: int = 8) -> str:
    """
    获取当前的日期和时间信息。

    返回格式化的日期、时间、星期、时间戳等完整时间信息。
    默认返回北京时间（UTC+8），可通过 timezone_offset 参数调整时区。

    Args:
        timezone_offset: 时区偏移量（小时），默认 8（北京时间/东八区）。
            常用值：0=UTC, 8=北京/新加坡, 9=东京, -5=纽约, -8=洛杉矶
    """
    tz = timezone(timedelta(hours=timezone_offset))
    now = datetime.now(tz)

    weekday_map = {
        0: "星期一", 1: "星期二", 2: "星期三",
        3: "星期四", 4: "星期五", 5: "星期六", 6: "星期日",
    }

    tz_sign = "+" if timezone_offset >= 0 else ""
    tz_name = f"UTC{tz_sign}{timezone_offset}"

    return json.dumps(
        {
            "date": now.strftime("%Y年%m月%d日"),
            "time": now.strftime("%H:%M:%S"),
            "weekday": weekday_map[now.weekday()],
            "timezone": tz_name,
            "iso_format": now.isoformat(),
            "timestamp": int(now.timestamp()),
        },
        ensure_ascii=False,
    )


@tool
def get_weather(city: str) -> str:
    """
    查询指定城市的实时天气（温度、湿度、风速、天气状况）。

    通过 Open-Meteo 公开接口查询，支持中文或英文城市名，例如「北京」「Shanghai」「东京」。
    适用于用户询问某地现在天气、气温、是否下雨等情况。

    Args:
        city: 城市名称，如「北京」「上海」「深圳」「Hangzhou」。
    """
    city = (city or "").strip()
    if not city:
        return json.dumps({"error": "请提供城市名称"}, ensure_ascii=False)

    try:
        geo_qs = urllib.parse.urlencode(
            {"name": city, "count": 1, "language": "zh", "format": "json"}
        )
        geo = _http_get_json(
            f"https://geocoding-api.open-meteo.com/v1/search?{geo_qs}"
        )
        results = geo.get("results") or []
        if not results:
            return json.dumps(
                {"error": f"未找到城市「{city}」，请换一个更常见的地名再试"},
                ensure_ascii=False,
            )

        place = results[0]
        lat = place["latitude"]
        lon = place["longitude"]
        resolved_name = place.get("name") or city
        country = place.get("country") or ""
        admin1 = place.get("admin1") or ""

        weather_qs = urllib.parse.urlencode(
            {
                "latitude": lat,
                "longitude": lon,
                "current": "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,apparent_temperature",
                "timezone": "auto",
            }
        )
        weather = _http_get_json(
            f"https://api.open-meteo.com/v1/forecast?{weather_qs}"
        )
        current = weather.get("current") or {}
        units = weather.get("current_units") or {}
        code = current.get("weather_code")
        condition = _WMO_WEATHER.get(code, f"未知天气码({code})")

        return json.dumps(
            {
                "city": resolved_name,
                "region": admin1,
                "country": country,
                "latitude": lat,
                "longitude": lon,
                "condition": condition,
                "temperature": current.get("temperature_2m"),
                "temperature_unit": units.get("temperature_2m", "°C"),
                "feels_like": current.get("apparent_temperature"),
                "humidity": current.get("relative_humidity_2m"),
                "humidity_unit": units.get("relative_humidity_2m", "%"),
                "wind_speed": current.get("wind_speed_10m"),
                "wind_speed_unit": units.get("wind_speed_10m", "km/h"),
                "observed_at": current.get("time"),
                "timezone": weather.get("timezone"),
                "source": "Open-Meteo",
            },
            ensure_ascii=False,
        )
    except urllib.error.HTTPError as e:
        return json.dumps(
            {"error": f"天气接口 HTTP 错误：{e.code} {e.reason}"},
            ensure_ascii=False,
        )
    except urllib.error.URLError as e:
        return json.dumps(
            {"error": f"无法连接天气接口：{e.reason}"},
            ensure_ascii=False,
        )
    except Exception as e:
        return json.dumps({"error": f"查询天气失败：{e}"}, ensure_ascii=False)


# 所有内置工具列表，供 ToolRegistry 批量注册
BUILTIN_TOOLS = [get_datetime, get_weather]
