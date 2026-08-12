// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interface/IDappLinkToken.sol";

abstract contract DappLinkTokenStorage is IDappLinkToken{
    uint256 public constant MaxTotalSupply = 200_000_000 * 10 ** 6;
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant SELL_FEE_BPS = 300;

    uint256 internal constant PRICE_DROP_3_BPS = 300;
    uint256 internal constant PRICE_DROP_6_BPS = 600;

    uint256 internal constant DOWN_TAX_3_BPS = 1_000;
    uint256 internal constant DOWN_TAX_6_BPS = 2_000;

    bool internal isOpenBuy;
    bool internal isOpenSell;

    bool internal isAllocation;
    bool internal slippageLock;

    DappLinkPool public dlPool;
    EnumerableSet.AddressSet whiteList;

    uint256 public _lpBurnedTokens;
    uint256 public latestChoPrice;
    uint256 public downsideTax;

    address public v2Router;
    address public v2Factory;
    address public mainPair;
    address public USDT;

    address public marking;
    address public operator;
    address public caller;
    address public treasureAddress;

    uint256[100] private __gap;
}
