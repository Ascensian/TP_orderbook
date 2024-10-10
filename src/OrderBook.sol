// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract OrderBook is ReentrancyGuard {
    enum OrderType {
        Buy,
        Sell
    }

    struct Order {
        uint256 id;
        address user;
        uint256 amount;
        uint256 price; // Price per token in wei
        OrderType orderType;
    }

    IERC20 public tokenA;
    IERC20 public tokenB;
    uint256 public nextOrderId;

    // Order books
    Order[] public buyOrders;
    Order[] public sellOrders;

    // Events
    event OrderPlaced(
        uint256 id,
        address indexed user,
        uint256 amount,
        uint256 price,
        OrderType orderType
    );
    event OrderFilled(
        uint256 id,
        address indexed user,
        uint256 amount,
        uint256 price,
        OrderType orderType
    );
    event OrderCancelled(
        uint256 id,
        address indexed user,
        uint256 amount,
        uint256 price,
        OrderType orderType
    );

    constructor(address _tokenA, address _tokenB) {
        require(_tokenA != _tokenB, "Tokens must be different");
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    // Place a buy order
    function placeBuyOrder(
        uint256 amount,
        uint256 price
    ) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(price > 0, "Price must be greater than zero");

        uint256 totalCost = amount * price;
        require(
            tokenB.transferFrom(msg.sender, address(this), totalCost),
            "Transfer of tokenB failed"
        );

        Order memory order = Order({
            id: nextOrderId,
            user: msg.sender,
            amount: amount,
            price: price,
            orderType: OrderType.Buy
        });

        buyOrders.push(order);
        emit OrderPlaced(nextOrderId, msg.sender, amount, price, OrderType.Buy);

        nextOrderId++;

        matchOrders();
    }

    // Place a sell order
    function placeSellOrder(
        uint256 amount,
        uint256 price
    ) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(price > 0, "Price must be greater than zero");

        require(
            tokenA.transferFrom(msg.sender, address(this), amount),
            "Transfer of tokenA failed"
        );

        Order memory order = Order({
            id: nextOrderId,
            user: msg.sender,
            amount: amount,
            price: price,
            orderType: OrderType.Sell
        });

        sellOrders.push(order);
        emit OrderPlaced(
            nextOrderId,
            msg.sender,
            amount,
            price,
            OrderType.Sell
        );

        nextOrderId++;

        matchOrders();
    }

    // Internal function to match orders
    function matchOrders() internal {
        uint256 i = 0;
        while (i < buyOrders.length) {
            Order storage buyOrder = buyOrders[i];
            bool matched = false;

            for (uint256 j = 0; j < sellOrders.length; j++) {
                Order storage sellOrder = sellOrders[j];

                if (buyOrder.price >= sellOrder.price) {
                    uint256 tradeAmount = buyOrder.amount < sellOrder.amount
                        ? buyOrder.amount
                        : sellOrder.amount;
                    uint256 tradePrice = sellOrder.price;

                    // Execute trade
                    require(
                        tokenA.transfer(buyOrder.user, tradeAmount),
                        "Transfer of tokenA failed"
                    );
                    require(
                        tokenB.transfer(
                            sellOrder.user,
                            tradeAmount * tradePrice
                        ),
                        "Transfer of tokenB failed"
                    );

                    emit OrderFilled(
                        buyOrder.id,
                        buyOrder.user,
                        tradeAmount,
                        tradePrice,
                        OrderType.Buy
                    );
                    emit OrderFilled(
                        sellOrder.id,
                        sellOrder.user,
                        tradeAmount,
                        tradePrice,
                        OrderType.Sell
                    );

                    // Update orders
                    buyOrder.amount -= tradeAmount;
                    sellOrder.amount -= tradeAmount;

                    if (sellOrder.amount == 0) {
                        removeSellOrder(j);
                        j--; // Adjust index after removal
                    }

                    matched = true;

                    if (buyOrder.amount == 0) {
                        removeBuyOrder(i);
                        i--; // Adjust index after removal
                        break;
                    }
                }
            }

            if (!matched) {
                i++;
            }
        }
    }

    // Remove a buy order by index
    function removeBuyOrder(uint256 index) internal {
        require(index < buyOrders.length, "Index out of bounds");
        buyOrders[index] = buyOrders[buyOrders.length - 1];
        buyOrders.pop();
    }

    // Remove a sell order by index
    function removeSellOrder(uint256 index) internal {
        require(index < sellOrders.length, "Index out of bounds");
        sellOrders[index] = sellOrders[sellOrders.length - 1];
        sellOrders.pop();
    }

    // Get all buy orders
    function getBuyOrders() external view returns (Order[] memory) {
        return buyOrders;
    }

    // Get all sell orders
    function getSellOrders() external view returns (Order[] memory) {
        return sellOrders;
    }
}
