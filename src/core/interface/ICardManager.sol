// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface ICardManager {
    event Deposit(
        address indexed tokenAddress,
        address indexed sender,
        uint256 amount
    );

    event Withdraw(
        address indexed tokenAddress,
        address sender,
        address withdrawAddress,
        uint256 amount
    );

    event DistributeReward(
        address indexed tokenAddress,
        address recipient,
        uint256 amount
    );

    event ValidatorMine (
        address indexed tokenAddress,
        address recipient,
        uint256 amount
    );

    event ValidatorMineClaim (
        address indexed tokenAddress,
        address recipient,
        uint256 amount
    );

    event CreateNFT(
        address indexed creator,
        uint256 _tokenId,
        string _imgUrl
    );

    function deposit() external payable returns (bool);
    function depositRewardErc20(address tokenAddress, uint256 amount) external returns (bool);
    function withdraw(address payable withdrawAddress, uint256 amount) external returns (bool);
    function withdrawErc20(address tokenAddress, address recipient, uint256 amount) external returns (bool);
    function validatorMine(address tokenAddress, address[] calldata miner, uint256[] calldata amount) external;
    function validatorMineClaim(address tokenAddress, uint256 amount) external;

    function buyCard(uint256 amount) external returns (bool, uint256);
    function buyCards(uint256 quantity, uint256 amount) external returns (bool, uint256[] memory);
    function batchTransferNft(address recipient, uint256[] calldata tokenIds) external returns (bool);
    function cardPrice() external view returns (uint256);
}
