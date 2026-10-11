#include "Policy.h"
#include <cstdlib>
#include <iostream>

int main() {
    int checks = 0;
    auto check = [&](bool value) { ++checks; if (!value) { std::cerr << "Failed check " << checks << '\n'; std::exit(1); } };
    const wchar_t* service[] = {L"probe", L"--service"};
    const wchar_t* worker[] = {L"probe", L"--worker"};
    const wchar_t* preflight[] = {L"probe", L"--preflight"};
    const wchar_t* extra[] = {L"probe", L"--worker", L"1"};
    const wchar_t* unsafe[] = {L"probe", L"--send-pin"};
    check(probe::ParseMode(2, service) == probe::Mode::Service);
    check(probe::ParseMode(2, worker) == probe::Mode::Worker);
    check(probe::ParseMode(2, preflight) == probe::Mode::Preflight);
    check(probe::ParseMode(3, extra) == probe::Mode::Invalid);
    check(probe::ParseMode(2, unsafe) == probe::Mode::Invalid);
    check(probe::ParseMode(1, service) == probe::Mode::Invalid);
    check(probe::ParseMode(2, nullptr) == probe::Mode::Invalid);
    probe::Gate ready{true, true, true, true, true, true, true, true, true, true, true, true};
    check(probe::MayMove(ready));
    bool probe::Gate::* fields[] = {&probe::Gate::system, &probe::Gate::protectedPaths, &probe::Gate::serviceParent,
        &probe::Gate::physicalConsole, &probe::Gate::active, &probe::Gate::locked, &probe::Gate::winsta0,
        &probe::Gate::threadWinlogon, &probe::Gate::inputWinlogon, &probe::Gate::beforeDeadline,
        &probe::Gate::noOnScreenKeyboard, &probe::Gate::noMouseButtonDown};
    for (auto field : fields) { auto g = ready; g.*field = false; check(!probe::MayMove(g)); check(!probe::MayRestore(g, true, true, {8, 3}, {8, 3})); }
    check(probe::MayRestore(ready, true, true, {8, 3}, {8, 3}));
    check(!probe::MayRestore(ready, false, true, {8, 3}, {8, 3}));
    check(!probe::MayRestore(ready, true, false, {8, 3}, {8, 3}));
    check(!probe::MayRestore(ready, true, true, {9, 3}, {8, 3}));
    check(!probe::MayRestore(ready, true, true, {8, 4}, {8, 3}));
    probe::Point target;
    check(probe::ChooseTarget({100, 100}, {0, 0}, {1920, 1080}, target) && target.x == 108 && target.y == 100);
    check(probe::ChooseTarget({1919, 0}, {0, 0}, {1920, 1080}, target) && target.x == 1911);
    check(probe::ChooseTarget({-1920, 0}, {-1920, 0}, {1920, 1080}, target) && target.x == -1912);
    check(!probe::ChooseTarget({100, 100}, {0, 0}, {10, 1080}, target));
    check(!probe::ChooseTarget({1920, 100}, {0, 0}, {1920, 1080}, target));
    check(!probe::ChooseTarget({-1, 100}, {0, 0}, {1920, 1080}, target));
    std::int32_t norm = 0;
    check(!probe::Normalize(0, 0, 0, norm));
    check(!probe::Normalize(0, 0, 32769, norm));
    check(!probe::Normalize(1920, 0, 1920, norm));
    check(!probe::Normalize(-1, 0, 1920, norm));
    for (const auto width : {1, 1920, 3840, 32768}) {
        bool roundtrip = true;
        for (int x = 0; x < width; ++x) {
            roundtrip &= probe::Normalize(x - 2000, -2000, width, norm);
            roundtrip &= (std::int64_t(norm) * width / 65536) == x;
        }
        check(roundtrip);
    }
    std::cout << checks << " no-input policy checks passed. No Win32 input APIs are linked.\n";
}
