# Sofatap roadmap

Updated October 13, 2026. This is the product direction, with acceptance goals rather than promised release dates.

**Feature delivery order:** free manual TV control → paid voice automation on Windows/macOS/Linux → paid voice automation on TVs. Existing desktop maintenance and release acceptance continue separately. Do not integrate the paid agent runtime ahead of the free TV milestone.

## Free: manual control of computers and TVs

The free product is an iPhone remote: the user moves, clicks, drags, scrolls and enters text. Basic voice-to-text remains part of this input experience. Dictating words into a field does not authorize an automated task.

1. **Current foundation — computers.** The iPhone app and receiver support manual control of Windows, macOS and supported Linux desktops. Text editing and input compatibility vary by platform and application; the [README](../README.md#platform-status) and [verification records](ACCEPTANCE.md) describe the actual scope. Keep improving these controls and their reliability.
2. **Next manual-control expansion — direct TVs.** Connect the iPhone to a supported TV without a separate computer. Prioritize the **Android/Google TV receiver feasibility milestone**: one native receiver codebase, native pairing UI, explicit permission setup and independently measured pointer/click/scroll/text capabilities. A receiver APK is a packaging choice, not proof of global mouse input. Keep Remote v2 direction navigation separately labeled and the LG webOS preview as another adapter; LG qualification is not a prerequisite for Android work. See the [implementation stages](research/tv-implementation-plan.md#shared-architecture-and-release-gates).

For every TV family, publish the tested model/OS/app matrix and distinguish these capabilities:

| Capability | Acceptance boundary |
| --- | --- |
| Pointer control | The TV renders and moves a real pointer; clicking reaches the intended target. Verify scrolling and any drag support independently in actual TV apps. |
| Focus navigation | Direction keys move focus and confirm/back activate navigation. Label this mode as navigation; it does not satisfy the mouse-control goal. |
| Unsupported | Clearly report unavailable actions. A moving decoration on the phone is not evidence of a TV pointer. |

Before calling a TV supported, verify discovery, explicit on-TV pairing, reconnection, disconnect, permissions and manual input on a physical TV. Document whether it needs a receiver installation. Pairing alone does not prove pointer control. The released app does not include direct-TV support. The development branch now contains an LG webOS pointer preview with manual IP pairing; see the [implementation plan](research/tv-implementation-plan.md) and [software verification](verification/webos-pointer-preview.md). Physical-TV qualification, discovery and TV text input remain open.

## Paid: speak a goal and complete multiple steps

The paid capability is voice-directed automation: interpret a goal, observe the device, perform a sequence of actions, verify the outcome and handle follow-up instructions. The user can see progress, stop the task and take over manually. Starting an automation session must be explicit and separate from ordinary dictation.

1. **First automation scope — Windows, macOS and Linux computers.** Qualify each OS and supported desktop/application combination separately. Evaluate pi-durable, Cua Driver and DeepSeek through the [architecture research](research/natural-language-pro.md). The intended product runs independently of Codex; this integration is still research, not a shipped capability.
2. **Later automation scope — TVs.** Extend goal-driven tasks only after manual TV control and reliable interface observation are established for that platform. Navigating a menu, seeing its result and interacting with protected playback may have different limits; qualify each supported scenario.

Acceptance requires repeatable multi-step tasks with measured completion, latency, cost and intervention rates on each platform. Test interruptions, changed windows, reconnection, immediate stopping and manual takeover. Consequential actions need a clear approval boundary, and uncertain actions must not be blindly replayed after recovery. Shared-Mac tests must preserve the user's normal display and input session through verified Yomado isolation.

## Release boundary

The current iPhone release is configured as free, with no IAP or subscription. Free manual TV control and paid computer/TV automation describe future scope. Basic keyboard entry and voice-to-text remain free input features; fees are for goal-driven automation. No TV compatibility, automation success, subscription price or delivery date is announced by this roadmap.
