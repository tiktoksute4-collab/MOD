/*
 * AimAssist.dylib  v2 — バチバチ磁力版
 * Fortnite iOS — UIApplication sendEvent: hook
 *
 * 仕組み:
 *   タッチ速度を3段階に分けてEMAスムージング強度を変える
 *
 *   HIGH  velocity (素早いフリック) → 強減速   = 標的に引き込まれる感
 *   MED   velocity (ゆっくり狙う)   → 超重い    = ネバネバ
 *   LOW   velocity (止まりかけ)     → ほぼ固定  = バチっと吸い付く
 *
 *   さらに「スティッキーバブル」: 一度LOW速度になったら抜け出しに
 *   余分な力が必要になる (ヒステリシス)。
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <math.h>

// ═══════════════════════════════════════════
//  設定 — ここを変えると強度が変わる
// ═══════════════════════════════════════════

// エイムゾーン: 画面の何%から右をエイム操作とみなすか
static const float kAimZoneStart = 0.48f;  // 0.48 = ほぼ中央から右

// 速度しきい値 (px / イベント)
static const float kVelHigh = 35.0f;   // これ以上: HIGH段階
static const float kVelMed  = 12.0f;   // これ以上: MED段階
static const float kVelLow  =  4.0f;   // これ以上: LOW段階
                                        // 未満: FROZEN (ほぼ動かない)

// EMA alpha値 (小さいほど強くスムージング、0に近いほど動かない)
static const float kAlphaHigh   = 0.22f;  // 高速: 大きく減速
static const float kAlphaMed    = 0.10f;  // 中速: ネバネバ
static const float kAlphaLow    = 0.04f;  // 低速: 吸い付く
static const float kAlphaFrozen = 0.01f;  // 極低速: ほぼ固定

// スティッキーバブル: LOW以下に入ったら抜け出すのに必要な速度倍率
// 1.0 = ヒステリシスなし、3.0 = LOWの3倍の速度で動かさないと抜けない
static const float kStickyHysteresis = 2.8f;

// デッドゾーン: これ以下の移動は無視 (指が静止中のドリフト防止)
static const float kDeadzone = 1.5f;

// ═══════════════════════════════════════════

#define MAX_TOUCHES 10

typedef enum {
    STAGE_FROZEN = 0,
    STAGE_LOW,
    STAGE_MED,
    STAGE_HIGH,
} VelocityStage;

typedef struct {
    CGPoint      smoothed;
    CGPoint      prev;
    BOOL         active;
    VelocityStage stage;    // 現在の段階 (ヒステリシス用)
    uintptr_t    key;
    BOOL         used;
} TouchState;

static TouchState g_slots[MAX_TOUCHES];
static BOOL       g_initialized = NO;

static void initSlots(void) {
    for (int i = 0; i < MAX_TOUCHES; i++) {
        g_slots[i].used   = NO;
        g_slots[i].active = NO;
    }
    g_initialized = YES;
}

static int findSlot(UITouch *t) {
    uintptr_t key = (uintptr_t)(__bridge void *)t;
    for (int i = 0; i < MAX_TOUCHES; i++) {
        if (g_slots[i].used && g_slots[i].key == key) return i;
    }
    for (int i = 0; i < MAX_TOUCHES; i++) {
        if (!g_slots[i].used) {
            g_slots[i].key  = key;
            g_slots[i].used = YES;
            return i;
        }
    }
    return 0;
}

static void freeSlot(UITouch *t) {
    uintptr_t key = (uintptr_t)(__bridge void *)t;
    for (int i = 0; i < MAX_TOUCHES; i++) {
        if (g_slots[i].used && g_slots[i].key == key) {
            g_slots[i].used   = NO;
            g_slots[i].active = NO;
            return;
        }
    }
}

// 速度からEMA alphaを決定 (ヒステリシスあり)
static float alphaForVelocity(float vel, VelocityStage *stage) {
    // ヒステリシス: 現在LOW/FROZEN状態なら抜け出しに必要な速度が上がる
    float exitMultiplier = 1.0f;
    if (*stage == STAGE_LOW || *stage == STAGE_FROZEN) {
        exitMultiplier = kStickyHysteresis;
    }

    if (vel >= kVelHigh * exitMultiplier) {
        *stage = STAGE_HIGH;
        return kAlphaHigh;
    } else if (vel >= kVelMed * exitMultiplier) {
        *stage = STAGE_MED;
        return kAlphaMed;
    } else if (vel >= kVelLow) {
        *stage = STAGE_LOW;
        return kAlphaLow;
    } else {
        *stage = STAGE_FROZEN;
        return kAlphaFrozen;
    }
}

static IMP g_origSendEvent = NULL;

// UITouchの_locationInWindowを直接書き換える
static void patchTouchLocation(UITouch *touch, CGPoint newLoc) {
    static ptrdiff_t offset = 0;
    static BOOL offsetFound = NO;
    if (!offsetFound) {
        Ivar ivar = class_getInstanceVariable([UITouch class], "_locationInWindow");
        if (ivar) {
            offset      = ivar_getOffset(ivar);
            offsetFound = YES;
        } else {
            return;
        }
    }
    CGPoint *ptr = (CGPoint *)((uint8_t *)(__bridge void *)touch + offset);
    *ptr = newLoc;
}

static void patched_sendEvent(id self, SEL _cmd, UIEvent *event) {
    if (!g_initialized) initSlots();

    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;

    for (UITouch *touch in [event allTouches]) {
        CGPoint loc   = [touch locationInView:nil];

        if (loc.x < screenW * kAimZoneStart) continue;

        int           slot = findSlot(touch);
        TouchState   *st   = &g_slots[slot];
        UITouchPhase  ph   = touch.phase;

        if (ph == UITouchPhaseBegan) {
            st->smoothed = loc;
            st->prev     = loc;
            st->active   = YES;
            st->stage    = STAGE_HIGH; // 開始はHIGHから
            continue;
        }
        if (ph == UITouchPhaseEnded || ph == UITouchPhaseCancelled) {
            freeSlot(touch);
            continue;
        }
        if (ph != UITouchPhaseMoved || !st->active) continue;

        CGFloat dx   = loc.x - st->prev.x;
        CGFloat dy   = loc.y - st->prev.y;
        CGFloat vel  = sqrtf(dx*dx + dy*dy);

        if (vel < kDeadzone) {
            // ドリフト無視: 座標を前のsmoothに固定
            patchTouchLocation(touch, st->smoothed);
            st->prev = loc;
            continue;
        }

        float   alpha    = alphaForVelocity(vel, &st->stage);
        CGPoint smoothed = {
            alpha * loc.x + (1.0f - alpha) * st->smoothed.x,
            alpha * loc.y + (1.0f - alpha) * st->smoothed.y,
        };

        patchTouchLocation(touch, smoothed);
        st->smoothed = smoothed;
        st->prev     = loc;
    }

    ((void(*)(id,SEL,UIEvent*))g_origSendEvent)(self, _cmd, event);
}

__attribute__((constructor))
static void AimAssistInit(void) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            Method m = class_getInstanceMethod([UIApplication class],
                                              @selector(sendEvent:));
            if (!m) return;
            g_origSendEvent = method_getImplementation(m);
            method_setImplementation(m, (IMP)patched_sendEvent);
            NSLog(@"[AimAssist v2] loaded — sticky=%.1fx", kStickyHysteresis);
        }
    );
}
