// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interface/ICardManager.sol";

abstract contract CardManagerStorage is ICardManager {
    uint256 public constant minAmount = 100 * 10 ** 18;

    enum StakingRewardType {
        SixThousandType,
        FourteenThousandType
    }

    enum DepositReward {
        DepositType,
        RewardType
    }

    address public constant NativeTokenAddress = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    address public underlyingToken;
    address public manager;
    address public fundManager;

    address public adminFeeVault;
    address public contractCaller;

    uint256 public _nextTokenId;

    string public nftJson;

    mapping(address => mapping(address => uint256)) public validatorBalance;

    uint256[100] private __gap;
}
