// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

interface IBasketsVrfConsumer {

    function makeRequestForBasket() external returns (uint256 requestId);
}