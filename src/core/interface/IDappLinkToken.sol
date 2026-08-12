// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IDappLinkToken {
    function burn(address user, uint256 _amount) external;
    function quote(uint256 amount) external view returns (uint256);
    function updateChoPrice() external;
    function getTreasureAddress() external view returns (address);
    function setMarking(address _marking) external;

    // 做市回收: 从交易对抽取代币到 marking 地址 (上限 pair 余额 1/3), 仅 marking 可调用
    function recycle(uint256 amount) external;


    //  合约事件
    event Burn(uint256 _burnAmount, uint256 _totalSupply);
    event SetPoolAddress(DappLinkPool pool);
    event UpdateChoPrice(uint256 timestamp, uint256 blockNumber, uint256 choPrice);
    event DeclineTaxApplied(uint256 amount, uint256 declineRate, uint256 toFomo);
    event Recycle(address indexed pair, address indexed marking, uint256 amount);
    event SetMarking(address indexed marking);
    event SetTreasureAddress(address indexed treasureAddress);

    struct DappLinkPool {
        address lpPool;
        address nftPool;
    }
}
