// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/OrderBook.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 tokens
contract MockERC20 is ERC20 {
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 initialSupply
    ) ERC20(name_, symbol_) {
        _mint(msg.sender, initialSupply);
    }
}

contract OrderBookTest is Test {
    OrderBook orderBook;
    MockERC20 tokenA;
    MockERC20 tokenB;

    address user1 = address(0x1);
    address user2 = address(0x2);

    function setUp() public {
        // Deploy mock tokens with initial supply
        tokenA = new MockERC20("Token A", "TKA", 1000 ether);
        tokenB = new MockERC20("Token B", "TKB", 1000 ether);

        // Deploy OrderBook contract
        orderBook = new OrderBook(address(tokenA), address(tokenB));

        // Distribute tokens to users
        tokenA.transfer(user1, 100 ether);
        tokenB.transfer(user1, 100 ether);

        tokenA.transfer(user2, 100 ether);
        tokenB.transfer(user2, 100 ether);
    }

    function testPlaceBuyOrder() public {
        vm.startPrank(user1);
        // Approve OrderBook to spend tokenB
        tokenB.approve(address(orderBook), 50 ether);

        // Place buy order: buy 10 TokenA at price 5 TokenB each
        orderBook.placeBuyOrder(10 ether, 5 ether);

        OrderBook.Order[] memory buys = orderBook.getBuyOrders();
        assertEq(buys.length, 1);
        assertEq(buys[0].user, user1);
        assertEq(buys[0].amount, 10 ether);
        assertEq(buys[0].price, 5 ether);
        assertEq(uint(buys[0].orderType), uint(OrderBook.OrderType.Buy));

        // Check tokenB balance
        assertEq(tokenB.balanceOf(user1), 100 ether - 50 ether);
        assertEq(tokenB.balanceOf(address(orderBook)), 50 ether);
        vm.stopPrank();
    }

    function testPlaceSellOrder() public {
        vm.startPrank(user2);
        // Approve OrderBook to spend tokenA
        tokenA.approve(address(orderBook), 20 ether);

        // Place sell order: sell 20 TokenA at price 4 TokenB each
        orderBook.placeSellOrder(20 ether, 4 ether);

        OrderBook.Order[] memory sells = orderBook.getSellOrders();
        assertEq(sells.length, 1);
        assertEq(sells[0].user, user2);
        assertEq(sells[0].amount, 20 ether);
        assertEq(sells[0].price, 4 ether);
        assertEq(uint(sells[0].orderType), uint(OrderBook.OrderType.Sell));

        // Check tokenA balance
        assertEq(tokenA.balanceOf(user2), 80 ether);
        assertEq(tokenA.balanceOf(address(orderBook)), 20 ether);
        vm.stopPrank();
    }

    function testMatchOrders() public {
        // User1 places a buy order
        vm.startPrank(user1);
        tokenB.approve(address(orderBook), 50 ether);
        orderBook.placeBuyOrder(10 ether, 5 ether);
        vm.stopPrank();

        // User2 places a sell order that matches the buy order
        vm.startPrank(user2);
        tokenA.approve(address(orderBook), 10 ether);
        orderBook.placeSellOrder(10 ether, 5 ether);
        vm.stopPrank();

        // After matching, buy and sell orders should be empty
        OrderBook.Order[] memory buys = orderBook.getBuyOrders();
        OrderBook.Order[] memory sells = orderBook.getSellOrders();
        assertEq(buys.length, 0);
        assertEq(sells.length, 0);

        // Check final balances
        // User1 should have received 10 TokenA and spent 50 TokenB
        assertEq(tokenA.balanceOf(user1), 100 ether + 10 ether);
        assertEq(tokenB.balanceOf(user1), 100 ether - 50 ether);

        // User2 should have received 50 TokenB and spent 10 TokenA
        assertEq(tokenA.balanceOf(user2), 100 ether - 10 ether);
        assertEq(tokenB.balanceOf(user2), 100 ether + 50 ether);

        // OrderBook should have zero balances of both tokens
        assertEq(tokenA.balanceOf(address(orderBook)), 0);
        assertEq(tokenB.balanceOf(address(orderBook)), 0);
    }

    function testPartialMatch() public {
        // User1 places a buy order for 15 TokenA at price 5 TokenB each
        vm.startPrank(user1);
        tokenB.approve(address(orderBook), 75 ether);
        orderBook.placeBuyOrder(15 ether, 5 ether);
        vm.stopPrank();

        // User2 places a sell order for 10 TokenA at price 5 TokenB each
        vm.startPrank(user2);
        tokenA.approve(address(orderBook), 10 ether);
        orderBook.placeSellOrder(10 ether, 5 ether);
        vm.stopPrank();

        // After matching:
        // Buy order should have 5 TokenA remaining
        // Sell order should be fully matched
        OrderBook.Order[] memory buys = orderBook.getBuyOrders();
        OrderBook.Order[] memory sells = orderBook.getSellOrders();
        assertEq(buys.length, 1);
        assertEq(buys[0].amount, 5 ether);
        assertEq(sells.length, 0);

        // Check final balances
        assertEq(tokenA.balanceOf(user1), 100 ether + 10 ether);
        assertEq(tokenB.balanceOf(user1), 100 ether - 50 ether);

        assertEq(tokenA.balanceOf(user2), 100 ether - 10 ether);
        assertEq(tokenB.balanceOf(user2), 100 ether + 50 ether);

        // OrderBook should hold 5 TokenA and 25 TokenB
        assertEq(tokenA.balanceOf(address(orderBook)), 5 ether);
        assertEq(tokenB.balanceOf(address(orderBook)), 25 ether);
    }

    function testNoMatch() public {
        // User1 places a buy order at price 5
        vm.startPrank(user1);
        tokenB.approve(address(orderBook), 50 ether);
        orderBook.placeBuyOrder(10 ether, 5 ether);
        vm.stopPrank();

        // User2 places a sell order at price 6 (no match)
        vm.startPrank(user2);
        tokenA.approve(address(orderBook), 10 ether);
        orderBook.placeSellOrder(10 ether, 6 ether);
        vm.stopPrank();

        // Orders should remain in the order books
        OrderBook.Order[] memory buys = orderBook.getBuyOrders();
        OrderBook.Order[] memory sells = orderBook.getSellOrders();
        assertEq(buys.length, 1);
        assertEq(sells.length, 1);

        // Check balances
        assertEq(tokenA.balanceOf(user2), 100 ether - 10 ether);
        assertEq(tokenB.balanceOf(user1), 100 ether - 50 ether);

        // OrderBook should hold 10 TokenA and 50 TokenB
        assertEq(tokenA.balanceOf(address(orderBook)), 10 ether);
        assertEq(tokenB.balanceOf(address(orderBook)), 50 ether);
    }

    function testMultipleMatches() public {
        // User1 places two buy orders
        vm.startPrank(user1);
        tokenB.approve(address(orderBook), 100 ether);
        orderBook.placeBuyOrder(10 ether, 5 ether);
        orderBook.placeBuyOrder(5 ether, 6 ether);
        vm.stopPrank();

        // User2 places two sell orders
        vm.startPrank(user2);
        tokenA.approve(address(orderBook), 8 ether);
        orderBook.placeSellOrder(8 ether, 5 ether);
        tokenA.approve(address(orderBook), 5 ether);
        orderBook.placeSellOrder(5 ether, 6 ether);
        vm.stopPrank();

        // After matching:
        // Buy order at 6 should match sell order at 5 (higher priority)
        // Buy order at 5 should match remaining sell orders

        // Check orders
        OrderBook.Order[] memory buys = orderBook.getBuyOrders();
        OrderBook.Order[] memory sells = orderBook.getSellOrders();
        assertEq(buys.length, 0);
        assertEq(sells.length, 0);

        // Check final balances
        // User1: bought 8 + 5 = 13 TokenA, spent (8*5) + (5*6) = 40 + 30 = 70 TokenB
        assertEq(tokenA.balanceOf(user1), 100 ether + 13 ether);
        assertEq(tokenB.balanceOf(user1), 100 ether - 70 ether);

        // User2: sold 8 + 5 = 13 TokenA, received (8*5) + (5*6) = 40 + 30 = 70 TokenB
        assertEq(tokenA.balanceOf(user2), 100 ether - 13 ether);
        assertEq(tokenB.balanceOf(user2), 100 ether + 70 ether);

        // OrderBook should hold zero tokens
        assertEq(tokenA.balanceOf(address(orderBook)), 0);
        assertEq(tokenB.balanceOf(address(orderBook)), 0);
    }

    function testInsufficientApprovalBuy() public {
        vm.startPrank(user1);
        // Do not approve tokenB
        vm.expectRevert("Transfer of tokenB failed");
        orderBook.placeBuyOrder(10 ether, 5 ether);
        vm.stopPrank();
    }

    function testInsufficientApprovalSell() public {
        vm.startPrank(user2);
        // Do not approve tokenA
        vm.expectRevert("Transfer of tokenA failed");
        orderBook.placeSellOrder(10 ether, 5 ether);
        vm.stopPrank();
    }
}
