// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title LendingOrderBook - A Central Limit Order Book (CLOB) for P2P lending
/// @notice Manages lending and borrowing orders with price-time priority matching
/// @dev Implements a two-sided order book where BUY = LEND and SELL = BORROW
contract LendingOrderBook is Ownable {

    /// @notice Represents the current state of an order
    /// @dev Used to track order lifecycle and matching status
    enum Status {
        OPEN,              // Order is active and available for matching
        PARTIALLY_FILLED,  // Order is partially matched but still active
        FILLED,           // Order is completely matched
        CANCELLED,        // Order was cancelled by the trader
        EXPIRED          // Order has expired (reserved for future use)
    }

    /// @notice Represents the side of an order
    /// @dev BUY represents lenders, SELL represents borrowers
    enum Side {
        BUY,   // Lender providing debt tokens
        SELL   // Borrower providing collateral
    }

    /// @notice Detailed information about an order in the book
    /// @dev Stores all relevant information for order matching and management
    struct Order {
        uint256 id;                // Unique identifier for the order
        address trader;            // Address that placed the order
        uint256 amount;            // Amount of tokens (quote for BUY, base for SELL)
        uint256 collateralAmount;  // Amount of collateral (only for SELL orders)
        uint256 price;             // Interest rate in basis points (e.g., 500 = 5%)
        Side side;                 // BUY (lend) or SELL (borrow)
        Status status;             // Current state of the order
    }

    /// @notice Information about matched orders
    /// @dev Used to return matching results and track partial fills
    struct MatchedInfo {
        uint256 orderId;           // ID of the matched order
        address trader;            // Address of the trader
        uint256 amount;            // Original order amount
        uint256 collateralAmount;  // Original collateral amount
        Side side;                 // Order side
        uint256 percentMatch;      // Percentage matched (1e18 = 100%)
        Status status;             // Final status after matching
    }

    /// @notice Emitted when a new order is placed in the book
    event OrderPlaced(
        uint256 orderId,
        address indexed trader,
        uint256 amount,
        uint256 collateralAmount,
        uint256 price,
        Side side,
        Status status
    );

    /// @notice Emitted when tokens are deposited into escrow
    event Deposit(address indexed trader, uint256 amount, Side side);

    /// @notice Emitted when orders are matched
    event OrderMatched(uint256 newOrderId, uint256 matchedOrderId, Status newOrderStatus, Status matchedOrderStatus);

    /// @notice Emitted when an order is removed from the queue
    event OrderRemovedFromQueue(uint256 orderId, uint256 price, Side side);

    /// @notice Emitted when tokens are transferred between parties
    event Transfer(address indexed from, address indexed to, uint256 amount, Side side);

    /// @notice Emitted when a limit order is cancelled
    event LimitOrderCancelled(uint256 orderId, Status status);

    /// @notice Emitted when the best price changes
    event BestPriceUpdated(uint256 price, Side side);

    /// @notice Token that can be borrowed (e.g., USDC)
    IERC20 public immutable quoteToken;

    /// @notice Token used as collateral (e.g., WETH)
    IERC20 public immutable baseToken;

    /// @notice Counter for generating unique order IDs
    uint256 public orderCount;

    /// @notice Current best (lowest) lending rate available
    uint256 public bestBuyPrice;

    /// @notice Tracks collateral balances for borrowers
    mapping(address => uint256) public baseBalances;

    /// @notice Tracks debt token balances for lenders
    mapping(address => uint256) public quoteBalances;

    /// @notice Maps traders to their orders
    mapping(address => Order[]) public traderOrders;

    /// @notice Main order book storage: price => side => orders
    /// @dev Primary structure for order matching and price discovery
    mapping(uint256 => mapping(Side => Order[])) public orderQueue;

    /// @notice Creates a new lending order book
    /// @param _quoteToken Address of the debt token
    /// @param _baseToken Address of the collateral token
    constructor(address _quoteToken, address _baseToken) Ownable(msg.sender) {
        quoteToken = IERC20(_quoteToken);
        baseToken = IERC20(_baseToken);
        bestBuyPrice = type(uint256).max; // Initialize to max value
    }

    /// @notice Updates the best buy price based on the order queue
    /// @dev Scans through buy orders to find the lowest valid price
    function _updateBestBuyPrice() internal {
        uint256 lowestPrice = type(uint256).max;
        bool foundValidPrice = false;

        // Iterate through all orders to find lowest price with valid orders
        // Since price is rate, then range will be from 0.5% (5e15) to 99.5% (995e15)
        // We increment by 0.5% (5e15)
        for (uint256 price = 5e15; price < 995e15; price+=5e15) {
            Order[] storage orders = orderQueue[price][Side.BUY];
            for (uint256 i = 0; i < orders.length; i++) {
                if (orders[i].status == Status.OPEN) {
                    lowestPrice = price;
                    foundValidPrice = true;
                    break;
                }
            }
            if (foundValidPrice) break;
        }

        // Only update and emit if price changed
        if (bestBuyPrice != lowestPrice) {
            bestBuyPrice = lowestPrice;
            emit BestPriceUpdated(lowestPrice, Side.BUY);
        }
    }

    /// @notice Gets the current best (lowest) lending rate available
    /// @return The best lending rate, or max uint256 if no valid lending orders exist
    function getBestBuyPrice() external view returns (uint256) {
        return bestBuyPrice;
    }

    /// @notice Places a new order in the book
    /// @dev Handles both lending (BUY) and borrowing (SELL) orders
    /// @param trader Address of the trader placing the order
    /// @param amount Amount of tokens to lend/borrow
    /// @param collateralAmount Amount of collateral (for SELL orders)
    /// @param price Interest rate in basis points
    /// @param side BUY (lend) or SELL (borrow)
    /// @return matchedBuyOrders Array of matched lending orders
    /// @return matchedSellOrders Array of matched borrowing orders
    function placeOrder(
        address trader,
        uint256 amount,
        uint256 collateralAmount,
        uint256 price,
        Side side
    ) external returns (MatchedInfo[] memory matchedBuyOrders, MatchedInfo[] memory matchedSellOrders) {
        // ---------------------------
        // 1. Transfer tokens to escrow
        // ---------------------------
        if (side == Side.BUY) {
            // LEND => deposit quoteToken
            require(
                quoteToken.transferFrom(msg.sender, address(this), amount),
                "quoteToken transfer failed"
            );
            quoteBalances[trader] += amount;
            emit Deposit(trader, amount, Side.BUY);
        } else {
            // BORROW => deposit baseToken
            require(
                baseToken.transferFrom(msg.sender, address(this), collateralAmount),
                "baseToken transfer failed"
            );
            baseBalances[trader] += collateralAmount;
            emit Deposit(trader, collateralAmount, Side.SELL);
        }

        // ---------------------------
        // 2. Build the new order
        // ---------------------------
        uint256 orderId = orderCount;
        orderCount++;

        Order memory newOrder = Order({
            id: orderId,
            trader: trader,
            amount: amount,
            collateralAmount: collateralAmount,
            price: price,
            side: side,
            status: Status.OPEN
        });

        emit OrderPlaced(orderId, trader, amount, collateralAmount, price, side, Status.OPEN);

        // Arrays to store matched results
        MatchedInfo[] memory tempBuyMatches  = new MatchedInfo[](50); // arbitrary max
        MatchedInfo[] memory tempSellMatches = new MatchedInfo[](50);
        uint256 buyMatchCount  = 0;
        uint256 sellMatchCount = 0;

        // Opposite side
        Side oppositeSide = (side == Side.BUY) ? Side.SELL : Side.BUY;
        Order[] storage oppQueue = orderQueue[price][oppositeSide];

        // Keep track of total matched for the newOrder
        uint256 totalMatchedForNewOrder;
        uint256 originalNewAmt = newOrder.amount;

        // ---------------------------
        // 3. Match loop
        // ---------------------------
        uint256 i = 0;
        while (i < oppQueue.length && newOrder.amount > 0) {
            Order storage matchOrder = oppQueue[i];

            // Skip if FILLED, CANCELLED, or same trader
            if (matchOrder.status == Status.FILLED || matchOrder.status == Status.CANCELLED || matchOrder.trader == trader) {
                i++;
                continue;
            }

            uint256 originalMatchAmt = matchOrder.amount;
            uint256 matchedAmt = 0;

            if (matchOrder.amount <= newOrder.amount) {
                // matchOrder fully filled
                matchedAmt        = matchOrder.amount;
                newOrder.amount  -= matchedAmt;
                matchOrder.amount = 0;
                matchOrder.status = Status.FILLED;

                if (newOrder.amount == 0) {
                    newOrder.status = Status.FILLED;
                } else {
                    newOrder.status = Status.PARTIALLY_FILLED;
                }

                emit OrderMatched(newOrder.id, matchOrder.id, newOrder.status, Status.FILLED);

                // Record how many tokens the newOrder matched
                totalMatchedForNewOrder += matchedAmt;

                // store matchOrder details
                _storeMatchInfo(matchOrder, matchedAmt, originalMatchAmt, tempBuyMatches, tempSellMatches, buyMatchCount, sellMatchCount);
                if (matchOrder.side == Side.BUY) {
                    buyMatchCount++;
                } else {
                    sellMatchCount++;
                }

                // Remove matchOrder from queue (swap+pop)
                _removeFromQueueByIndex(oppQueue, i, price, matchOrder.side);

            } else {
                // newOrder is fully filled, matchOrder partial
                matchedAmt         = newOrder.amount;
                matchOrder.amount -= matchedAmt;
                matchOrder.status  = Status.PARTIALLY_FILLED;
                newOrder.amount    = 0;
                newOrder.status    = Status.FILLED;

                emit OrderMatched(newOrder.id, matchOrder.id, Status.FILLED, Status.PARTIALLY_FILLED);

                totalMatchedForNewOrder += matchedAmt;

                // matchOrder
                _storeMatchInfo(matchOrder, matchedAmt, originalMatchAmt, tempBuyMatches, tempSellMatches, buyMatchCount, sellMatchCount);
                if (matchOrder.side == Side.BUY) {
                    buyMatchCount++;
                } else {
                    sellMatchCount++;
                }

                // newOrder is exhausted => break
                i++;
                break;
            }

            i++;
        }

        // ----------------------------------
        // 4. If newOrder is STILL OPEN
        // ----------------------------------
        if (newOrder.status == Status.OPEN) {
            // No fill happened; push entire order
            orderQueue[newOrder.price][newOrder.side].push(newOrder);
            traderOrders[newOrder.trader].push(newOrder);
        } else {
            // (FILLED or PARTIALLY_FILLED)
            // We record it once in traderOrders
            traderOrders[newOrder.trader].push(newOrder);
        }

        // ----------------------------------
        // 5. *Now* store newOrder's matched info if it partially or fully filled
        //    (Because newOrder is only one, we do this exactly once).
        // ----------------------------------
        if (totalMatchedForNewOrder > 0) {
            // We'll store newOrder's final leftover
            // partial fill leftover = newOrder.amount
            // final status is newOrder.status
            // matched fraction = totalMatchedForNewOrder / originalNewAmt

            uint256 denom = (originalNewAmt == 0) ? 1 : originalNewAmt;
            uint256 pMatch = (totalMatchedForNewOrder * 1e18) / denom;

            MatchedInfo memory newOrderInfo = MatchedInfo({
                orderId: newOrder.id,
                trader: newOrder.trader,
                amount: originalNewAmt,
                collateralAmount: newOrder.collateralAmount,
                side: newOrder.side,
                percentMatch: pMatch,
                status: newOrder.status
            });

            // If newOrder is BUY, add to buy array; else to sell array
            if (newOrder.side == Side.BUY) {
                tempBuyMatches[buyMatchCount] = newOrderInfo;
                buyMatchCount++;
            } else {
                tempSellMatches[sellMatchCount] = newOrderInfo;
                sellMatchCount++;
            }
        }

        // ----------------------------------
        // 6. Build final matched arrays
        // ----------------------------------
        matchedBuyOrders  = new MatchedInfo[](buyMatchCount);
        matchedSellOrders = new MatchedInfo[](sellMatchCount);

        uint256 buyIdx  = 0;
        uint256 sellIdx = 0;

        // copy buy matches
        for (uint256 j = 0; j < 50; j++) {
            MatchedInfo memory infoB = tempBuyMatches[j];
            if (infoB.trader != address(0)) {
                matchedBuyOrders[buyIdx] = infoB;
                buyIdx++;
                if (buyIdx == buyMatchCount) break;
            }
        }

        // copy sell matches
        for (uint256 k = 0; k < 50; k++) {
            MatchedInfo memory infoS = tempSellMatches[k];
            if (infoS.trader != address(0)) {
                matchedSellOrders[sellIdx] = infoS;
                sellIdx++;
                if (sellIdx == sellMatchCount) break;
            }
        }

        // After matching logic, update best price if this is a buy order
        if (side == Side.BUY && newOrder.status == Status.OPEN) {
            if (price < bestBuyPrice) {
                bestBuyPrice = price;
                emit BestPriceUpdated(price, Side.BUY);
            }
        }

        // Return both arrays
        return (matchedBuyOrders, matchedSellOrders);
    }

    /// @notice Cancels an open order
    /// @dev Refunds escrowed tokens and updates order status
    /// @param trader Address of the trader who placed the order
    /// @param orderId ID of the order to cancel
    function cancelOrder(address trader, uint256 orderId) external {
        Order[] storage orders = traderOrders[trader];
        for (uint256 i = 0; i < orders.length; i++) {
            if (orders[i].id == orderId && orders[i].status == Status.OPEN) {
                Order storage orderFound = orders[i];
                orderFound.status = Status.CANCELLED;
                emit LimitOrderCancelled(orderId, Status.CANCELLED);

                // Remove from queue if present
                uint256 idx = _findOrderIndex(
                    orderQueue[orderFound.price][orderFound.side],
                    orderId
                );
                if (idx < orderQueue[orderFound.price][orderFound.side].length) {
                    _removeFromQueueByIndex(
                        orderQueue[orderFound.price][orderFound.side],
                        idx,
                        orderFound.price,
                        orderFound.side
                    );

                    // If this was a buy order and potentially the best price, update best price
                    if (orderFound.side == Side.BUY && orderFound.price == bestBuyPrice) {
                        _updateBestBuyPrice();
                    }
                }

                // Refund escrow
                if (orderFound.side == Side.BUY) {
                    uint256 refundAmt = orderFound.amount;
                    require(quoteBalances[trader] >= refundAmt, "Insufficient quote escrow");
                    quoteBalances[trader] -= refundAmt;
                    require(quoteToken.transfer(trader, refundAmt), "Refund failed");
                } else {
                    uint256 refundCollat = orderFound.collateralAmount;
                    require(baseBalances[trader] >= refundCollat, "Insufficient base escrow");
                    baseBalances[trader] -= refundCollat;
                    require(baseToken.transfer(trader, refundCollat), "Refund failed");
                }
                break;
            }
        }
    }

    /// @notice Transfers tokens between parties
    /// @dev Only callable by owner (e.g., router contract)
    /// @param from Address to transfer from
    /// @param to Address to transfer to
    /// @param amount Amount of tokens to transfer
    /// @param side Determines which token to transfer (BUY=quote, SELL=base)
    function transferFrom(
        address from,
        address to,
        uint256 amount,
        Side side
    ) external onlyOwner {
        if (side == Side.BUY) {
            require(quoteBalances[from] >= amount, "Not enough quote escrow");
            quoteBalances[from] -= amount;
            require(quoteToken.transfer(to, amount), "Transfer failed");
        } else {
            require(baseBalances[from] >= amount, "Not enough base escrow");
            baseBalances[from] -= amount;
            require(baseToken.transfer(to, amount), "Transfer failed");
        }
        emit Transfer(from, to, amount, side);
    }

    /// @notice Gets all orders placed by a trader
    /// @param trader Address of the trader
    /// @return Array of orders placed by the trader
    function getUserOrders(address trader) external view returns (Order[] memory) {
        return traderOrders[trader];
    }

    /// @notice Stores match information for an order
    /// @dev Helper function for tracking matched orders
    /// @param matchOrder The order that was matched
    /// @param matchedAmt Amount that was matched
    /// @param originalMatchAmt Original order amount
    /// @param buyArr Array to store BUY matches
    /// @param sellArr Array to store SELL matches
    /// @param buyCount Current count of BUY matches
    /// @param sellCount Current count of SELL matches
    function _storeMatchInfo(
        Order storage matchOrder,
        uint256 matchedAmt,
        uint256 originalMatchAmt,
        MatchedInfo[] memory buyArr,
        MatchedInfo[] memory sellArr,
        uint256 buyCount,
        uint256 sellCount
    ) internal view {
        // matchedAmt / originalMatchAmt
        uint256 denom = (originalMatchAmt == 0) ? 1 : originalMatchAmt;
        uint256 pMatch = (matchedAmt * 1e18) / denom;

        MatchedInfo memory info = MatchedInfo({
            orderId: matchOrder.id,
            trader: matchOrder.trader,
            amount: originalMatchAmt,  // original matched
            collateralAmount: matchOrder.collateralAmount,
            side: matchOrder.side,
            percentMatch: pMatch,
            status: matchOrder.status
        });

        if (matchOrder.side == Side.BUY) {
            buyArr[buyCount] = info;
        } else {
            sellArr[sellCount] = info;
        }
    }

    /// @notice Removes an order from the queue
    /// @dev Helper function for order cancellation and matching
    /// @param queue The order queue to remove from
    /// @param index Index of the order to remove
    /// @param price Price level of the order
    /// @param side Side of the order book
    function _removeFromQueueByIndex(
        Order[] storage queue,
        uint256 index,
        uint256 price,
        Side side
    ) internal {
        uint256 length = queue.length;
        if (length > 0 && index < length) {
            uint256 rmOrderId = queue[index].id;
            queue[index] = queue[length - 1];
            queue.pop();

            emit OrderRemovedFromQueue(rmOrderId, price, side);
        }
    }
    
    /// @notice Finds the index of an order in the queue
    /// @dev Helper function for order cancellation
    /// @param orders Array of orders to search
    /// @param orderId ID of the order to find
    /// @return Index of the order, or max uint256 if not found
    function _findOrderIndex(Order[] storage orders, uint256 orderId) internal view returns (uint256) {
        for (uint256 i = 0; i < orders.length; i++) {
            // Only remove if status == OPEN
            if (orders[i].id == orderId && orders[i].status == Status.OPEN) {
                return i;
            }
        }
        return type(uint256).max;
    }
}
