// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

enum SubscriptionPlan {
    Basic,
    Premium,
    Vip
}

struct Provider {
    uint32 subscriberCount;
    uint128 balance;
    bool active;
}

struct Subscriber {
    uint8 plan;
    uint128 balance;
    bool paused;
}