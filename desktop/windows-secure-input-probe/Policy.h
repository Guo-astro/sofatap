#pragma once
#include <cstdint>
#include <string_view>

namespace probe {
enum class Mode { Invalid, Service, Worker, Preflight };
inline Mode ParseMode(int argc, const wchar_t* const* argv) noexcept {
    if (argc != 2 || !argv || !argv[1]) return Mode::Invalid;
    const std::wstring_view value(argv[1]);
    if (value == L"--service") return Mode::Service;
    if (value == L"--worker") return Mode::Worker;
    if (value == L"--preflight") return Mode::Preflight;
    return Mode::Invalid;
}

// Each field must be observed, not inferred from a process being launched.
struct Gate {
    bool system = false;
    bool protectedPaths = false;
    bool serviceParent = false;
    bool physicalConsole = false;
    bool active = false;
    bool locked = false;
    bool winsta0 = false;
    bool threadWinlogon = false;
    bool inputWinlogon = false;
    bool beforeDeadline = false;
    bool noOnScreenKeyboard = false;
    bool noMouseButtonDown = false;
};
inline bool MayMove(const Gate& g) noexcept {
    return g.system && g.protectedPaths && g.serviceParent && g.physicalConsole
        && g.active && g.locked && g.winsta0 && g.threadWinlogon
        && g.inputWinlogon && g.beforeDeadline && g.noOnScreenKeyboard && g.noMouseButtonDown;
}
struct Point { std::int32_t x = 0, y = 0; };
inline bool SamePoint(Point a, Point b) noexcept { return a.x == b.x && a.y == b.y; }
inline bool MayRestore(const Gate& g, bool accepted, bool observed, Point current, Point injected) noexcept {
    return MayMove(g) && accepted && observed && SamePoint(current, injected);
}
inline bool ChooseTarget(Point original, Point monitorOrigin, Point monitorExtent, Point& target) noexcept {
    if (monitorExtent.x < 17 || monitorExtent.y < 1) return false;
    const std::int64_t right = std::int64_t(monitorOrigin.x) + monitorExtent.x;
    const std::int64_t bottom = std::int64_t(monitorOrigin.y) + monitorExtent.y;
    if (original.x < monitorOrigin.x || original.x >= right || original.y < monitorOrigin.y || original.y >= bottom) return false;
    target = original;
    target.x += original.x + std::int64_t(8) < right ? 8 : -8;
    return true;
}
// An absolute input addresses the centre of a pixel in the virtual desktop.
// We still require an exact GetCursorPos observation, never assume this mapping worked.
inline bool Normalize(std::int32_t value, std::int32_t origin, std::int32_t extent, std::int32_t& result) noexcept {
    const std::int64_t offset = std::int64_t(value) - origin;
    if (extent <= 0 || extent > 32768 || offset < 0 || offset >= extent) return false;
    result = static_cast<std::int32_t>(((offset * 2 + 1) * 65536) / (std::int64_t(extent) * 2));
    return result >= 0 && result <= 65535;
}
} // namespace probe
