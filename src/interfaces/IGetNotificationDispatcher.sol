// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import { IRWAPriceNotificationDispatcher } from "@tangible/interfaces/IRWAPriceNotificationDispatcher.sol";

interface IGetNotificationDispatcher {

    function notificationDispatcher() external returns (IRWAPriceNotificationDispatcher);
}