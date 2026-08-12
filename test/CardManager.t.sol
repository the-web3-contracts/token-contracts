// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgrades/contracts/utils/PausableUpgradeable.sol";

import {CardManager} from "../src/core/contracts/CardManager.sol";

contract CardMockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract RejectNativeTransfer {
    receive() external payable {
        revert("rejected");
    }
}

contract CardManagerTest is Test, IERC721Receiver {
    CardManager internal cardManager;
    CardMockERC20 internal token;

    address internal owner = makeAddr("owner");
    address internal manager = makeAddr("manager");
    address internal contractCaller = makeAddr("contractCaller");
    address internal fundManager = makeAddr("fundManager");
    address internal buyer = makeAddr("buyer");
    address internal recipient = makeAddr("recipient");

    uint256 internal constant CARD_PRICE = 100 ether;

    function setUp() public {
        token = new CardMockERC20();
        CardManager implementation = new CardManager();
        bytes memory initData = abi.encodeCall(
            CardManager.initialize, (owner, manager, contractCaller, address(token), "ipfs://card.json")
        );
        cardManager = CardManager(payable(address(new ERC1967Proxy(address(implementation), initData))));

        vm.prank(owner);
        cardManager.setFundManager(fundManager);
        token.mint(buyer, 2_000_000 ether);
    }

    function testInitializeSetsConfiguration() public view {
        assertEq(cardManager.owner(), owner);
        assertEq(cardManager.manager(), manager);
        assertEq(cardManager.contractCaller(), contractCaller);
        assertEq(cardManager.fundManager(), fundManager);
        assertEq(cardManager.underlyingToken(), address(token));
        assertEq(cardManager.name(), "The Web3 VIP Card");
        assertEq(cardManager.symbol(), "TheWeb3 VIP");
        assertEq(cardManager.nftJson(), "ipfs://card.json");
        assertEq(cardManager.cardPrice(), CARD_PRICE);
    }

    function testImplementationCannotBeInitialized() public {
        CardManager implementation = new CardManager();
        vm.expectRevert();
        implementation.initialize(owner, manager, contractCaller, address(token), "uri");
    }

    function testOwnerCanUpdateRoles() public {
        address newManager = makeAddr("newManager");
        address newCaller = makeAddr("newCaller");
        address newFundManager = makeAddr("newFundManager");

        vm.startPrank(owner);
        cardManager.setManager(newManager);
        cardManager.setContractCaller(newCaller);
        cardManager.setFundManager(newFundManager);
        vm.stopPrank();

        assertEq(cardManager.manager(), newManager);
        assertEq(cardManager.contractCaller(), newCaller);
        assertEq(cardManager.fundManager(), newFundManager);
    }

    function testRoleSettersRejectUnauthorizedAndZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, buyer));
        vm.prank(buyer);
        cardManager.setManager(buyer);

        vm.startPrank(owner);
        vm.expectRevert("CardManager: manager cannot be zero address");
        cardManager.setManager(address(0));
        vm.expectRevert("CardManager: _contractCaller cannot be zero address");
        cardManager.setContractCaller(address(0));
        vm.expectRevert("CardManager: fund manager cannot be zero address");
        cardManager.setFundManager(address(0));
        vm.stopPrank();
    }

    function testDepositAndReceiveNativeToken() public {
        vm.deal(buyer, 3 ether);
        vm.prank(buyer);
        assertTrue(cardManager.deposit{value: 1 ether}());
        vm.prank(buyer);
        (bool success,) = address(cardManager).call{value: 2 ether}("");

        assertTrue(success);
        assertEq(address(cardManager).balance, 3 ether);
    }

    function testDepositRewardErc20() public {
        vm.prank(buyer);
        token.approve(address(cardManager), 50 ether);
        vm.prank(buyer);
        assertTrue(cardManager.depositRewardErc20(address(token), 50 ether));
        assertEq(token.balanceOf(address(cardManager)), 50 ether);

        vm.expectRevert("CardManager: depositRewardErc20 invalid amount");
        cardManager.depositRewardErc20(address(token), 0);
        vm.expectRevert("CardManager: depositRewardErc20 token address is zero address");
        cardManager.depositRewardErc20(address(0), 1);
    }

    function testFundManagerCanWithdrawNativeAndErc20() public {
        vm.deal(address(cardManager), 2 ether);
        token.mint(address(cardManager), 80 ether);

        vm.startPrank(fundManager);
        assertTrue(cardManager.withdraw(payable(recipient), 1 ether));
        assertTrue(cardManager.withdrawErc20(address(token), recipient, 30 ether));
        vm.stopPrank();

        assertEq(recipient.balance, 1 ether);
        assertEq(token.balanceOf(recipient), 30 ether);
    }

    function testWithdrawChecksRoleBalanceAndNativeTransfer() public {
        vm.expectRevert("onlyFundManager");
        cardManager.withdraw(payable(recipient), 1);

        vm.startPrank(fundManager);
        vm.expectRevert("CardManager withdraw: insufficient native token balance in contract");
        cardManager.withdraw(payable(recipient), 1);
        vm.expectRevert("CardManager: withdraw erc20 amount more token balance in this contracts");
        cardManager.withdrawErc20(address(token), recipient, 1);

        vm.deal(address(cardManager), 1 ether);
        RejectNativeTransfer rejector = new RejectNativeTransfer();
        vm.expectRevert("CardManager: native transfer failed");
        cardManager.withdraw(payable(address(rejector)), 1 ether);
        vm.stopPrank();
    }

    function testValidatorMineAndClaim() public {
        address[] memory miners = new address[](2);
        miners[0] = buyer;
        miners[1] = recipient;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 20 ether;
        amounts[1] = 30 ether;
        token.mint(address(cardManager), 50 ether);

        vm.prank(contractCaller);
        cardManager.validatorMine(address(token), miners, amounts);
        assertEq(cardManager.validatorBalance(address(token), buyer), 20 ether);

        vm.prank(buyer);
        cardManager.validatorMineClaim(address(token), 12 ether);
        assertEq(cardManager.validatorBalance(address(token), buyer), 8 ether);
        assertEq(token.balanceOf(buyer), 2_000_012 ether);
    }

    function testValidatorMineRejectsInvalidCalls() public {
        address[] memory miners = new address[](1);
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert("onlyContractCaller");
        cardManager.validatorMine(address(token), miners, amounts);
        vm.expectRevert("CardManager: miner and amount length mismatch");
        vm.prank(contractCaller);
        cardManager.validatorMine(address(token), miners, amounts);

        vm.expectRevert("CardManager: validator balance is not enough");
        vm.prank(buyer);
        cardManager.validatorMineClaim(address(token), 1);
    }

    function testBuyCardTransfersPriceAndMintsNft() public {
        vm.prank(buyer);
        token.approve(address(cardManager), CARD_PRICE);
        vm.prank(buyer);
        (bool success, uint256 tokenId) = cardManager.buyCard(CARD_PRICE);

        assertTrue(success);
        assertEq(tokenId, 0);
        assertEq(cardManager.ownerOf(tokenId), buyer);
        assertEq(cardManager.tokenURI(tokenId), "ipfs://card.json");
        assertEq(cardManager.uri(tokenId), "ipfs://card.json");
        assertEq(token.balanceOf(address(cardManager)), CARD_PRICE);
        assertEq(cardManager._nextTokenId(), 1);
    }

    function testBuyCardsMintsRequestedQuantity() public {
        vm.prank(buyer);
        token.approve(address(cardManager), 3 * CARD_PRICE);
        vm.prank(buyer);
        (bool success, uint256[] memory tokenIds) = cardManager.buyCards(3, 3 * CARD_PRICE);

        assertTrue(success);
        assertEq(tokenIds.length, 3);
        assertEq(tokenIds[0], 0);
        assertEq(tokenIds[2], 2);
        assertEq(cardManager.balanceOf(buyer), 3);
        assertEq(token.balanceOf(address(cardManager)), 3 * CARD_PRICE);
    }

    function testBuyCardsRejectsInvalidQuantityAllowanceAndAmount() public {
        vm.expectRevert("CardManager buyCards: quantity must be greater than zero");
        vm.prank(buyer);
        cardManager.buyCards(0, 0);

        vm.expectRevert("CardManager buyCard: User allowance must more than price");
        vm.prank(buyer);
        cardManager.buyCard(CARD_PRICE);

        vm.prank(buyer);
        token.approve(address(cardManager), CARD_PRICE);
        vm.expectRevert("CardManager buyCard: amount must be more than price");
        vm.prank(buyer);
        cardManager.buyCard(CARD_PRICE - 1);
    }

    function testBatchTransferNft() public {
        vm.prank(buyer);
        token.approve(address(cardManager), 2 * CARD_PRICE);
        vm.prank(buyer);
        (, uint256[] memory tokenIds) = cardManager.buyCards(2, 2 * CARD_PRICE);

        vm.prank(buyer);
        assertTrue(cardManager.batchTransferNft(recipient, tokenIds));
        assertEq(cardManager.ownerOf(0), recipient);
        assertEq(cardManager.ownerOf(1), recipient);
    }

    function testBatchTransferRejectsInvalidRecipientEmptyAndNonOwner() public {
        uint256[] memory emptyIds = new uint256[](0);
        vm.expectRevert("CardManager: recipient is zero address");
        cardManager.batchTransferNft(address(0), emptyIds);
        vm.expectRevert("CardManager: tokenIds is empty");
        cardManager.batchTransferNft(recipient, emptyIds);

        vm.prank(buyer);
        token.approve(address(cardManager), CARD_PRICE);
        vm.prank(buyer);
        (, uint256 tokenId) = cardManager.buyCard(CARD_PRICE);
        uint256[] memory ids = new uint256[](1);
        ids[0] = tokenId;
        vm.expectRevert("CardManager: caller is not token owner");
        cardManager.batchTransferNft(recipient, ids);
    }

    function testManagerCanPauseAndPausedFunctionsRevert() public {
        vm.expectRevert("onlyManager");
        cardManager.pause();
        vm.prank(manager);
        cardManager.pause();
        assertTrue(cardManager.paused());

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        cardManager.deposit{value: 0}();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        cardManager.depositRewardErc20(address(token), 1);

        vm.prank(manager);
        cardManager.unpause();
        assertFalse(cardManager.paused());
    }

    function testTokenUriRejectsNonexistentToken() public {
        vm.expectRevert("ERC721Metadata: URI query for nonexistent token");
        cardManager.tokenURI(99);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
