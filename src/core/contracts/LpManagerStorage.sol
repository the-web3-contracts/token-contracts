// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "../interface/ILpManager.sol";

abstract contract LpManagerStorage is ILpManager {
    address public USDT;

    address public underlyingToken;

    address public manager;

    EnumerableSet.AddressSet internal authorizedCallers;

    address public v2Router;

    uint256[100] private __gap;
}
