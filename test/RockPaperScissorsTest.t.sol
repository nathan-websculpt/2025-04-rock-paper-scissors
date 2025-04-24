// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/RockPaperScissors.sol";
import "../src/WinningToken.sol";

contract Reenter {
    RockPaperScissors public game;
    uint256 public gameId;

    constructor(address payable _game, uint256 _betAmount, uint256 _timeout, uint256 _totalTurns) payable {
        game = RockPaperScissors(_game);
        gameId = game.createGameWithEth{value: _betAmount}(_totalTurns, _timeout);
    }

    fallback() external payable {
        bytes memory data = abi.encodeWithSignature("cancelGame(uint256)", gameId);
        if (msg.sender.balance > msg.value) {
            (msg.sender).call(data);
        }
    }
}

contract RockPaperScissorsTest is Test {
    // Events for testing
    event GameCreated(uint256 indexed gameId, address indexed creator, uint256 bet, uint256 totalTurns);
    event PlayerJoined(uint256 indexed gameId, address indexed player);
    event MoveCommitted(uint256 indexed gameId, address indexed player, uint256 currentTurn);
    event MoveRevealed(
        uint256 indexed gameId, address indexed player, RockPaperScissors.Move move, uint256 currentTurn
    );
    event TurnCompleted(uint256 indexed gameId, address winner, uint256 currentTurn);
    event GameFinished(uint256 indexed gameId, address winner, uint256 prize);
    event GameCancelled(uint256 indexed gameId);
    event JoinTimeoutUpdated(uint256 oldTimeout, uint256 newTimeout);
    event FeeCollected(uint256 gameId, uint256 feeAmount);
    event FeeWithdrawn(address indexed admin, uint256 amount);

    // Contracts
    RockPaperScissors public game;
    WinningToken public token;

    // Test accounts
    address public admin;
    address public playerA;
    address public playerB;
    address public playerC;

    // Test constants
    uint256 constant BET_AMOUNT = 0.1 ether;
    uint256 constant TIMEOUT = 10 minutes;
    uint256 constant TOTAL_TURNS = 3; // Must be odd

    // Game ID for tests
    uint256 public gameId;

    // Player balances
    uint256 public playerAInitialBalance;
    uint256 public playerANewBalance;
    uint256 public playerBInitialBalance;
    uint256 public playerBNewBalance;
    uint256 public playerCInitialBalance;
    uint256 public playerCNewBalance;

    // Contract balances
    uint256 public contractInitialBalance;
    uint256 public contractNewBalance;
    uint256 public contractFinalBalance;

    // Setup before each test
    function setUp() public {
        // Set up addresses
        admin = address(this);
        playerA = makeAddr("playerA");
        playerB = makeAddr("playerB");
        playerC = makeAddr("playerC");  

        // Fund the players
        vm.deal(playerA, 10 ether);
        vm.deal(playerB, 10 ether);
        vm.deal(playerC, 10 ether);

        // Deploy contracts
        game = new RockPaperScissors();
        token = WinningToken(game.winningToken());

        // Mint some tokens for players for token tests
        vm.prank(address(game));
        token.mint(playerA, 10);

        vm.prank(address(game));
        token.mint(playerB, 10);

        vm.prank(address(game));
        token.mint(playerC, 10);
    }

    
    // Test cancelGame against reentrancy
    function testReentrancyCancel() public {
        vm.deal(address(game), 10 ether); 
        Reenter reenter = (new Reenter){value: BET_AMOUNT}(payable(game), BET_AMOUNT, TIMEOUT, TOTAL_TURNS);

        assertEq(address(reenter).balance, 0);

        // Join the game
        console.log(address(playerB).balance);
        vm.startPrank(playerB);        
        game.joinGameWithEth{value: BET_AMOUNT}(gameId);
        vm.stopPrank();
        console.log(address(playerB).balance);

        // Verify game details
        (
            address storedPlayerA,
            address storedPlayerB,
            uint256 bet,
            uint256 timeoutInterval,
            ,
            ,
            ,
            uint256 totalTurns,
            uint256 currentTurn,
            ,
            ,
            ,
            ,
            ,
            ,
            RockPaperScissors.GameState state
        ) = game.games(gameId);

        assertEq(storedPlayerA, address(reenter));
        assertEq(storedPlayerB, playerB);
        assertEq(bet, BET_AMOUNT);
        assertEq(timeoutInterval, TIMEOUT);
        assertEq(totalTurns, TOTAL_TURNS);
        assertEq(currentTurn, 1);
        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Created));

        // Try to cancel game using reentrancy
        vm.prank(payable(reenter));
        game.cancelGame(gameId);

        // assertGt(address(reenter).balance, 9 ether);
        assertEq(address(reenter).balance, BET_AMOUNT);
        // console.log(address(game).balance);
        // console.log(address(reenter).balance);
        console.log(address(playerB).balance);
    }

    // Inconsistent Checks On game.bet val In joinGameWithEth Function Allows Player B To Join Game Without Staking
    // https://codehawks.cyfrin.io/c/2025-04-rock-paper-scissors/s/3
    // forge test --mt testJoinGameWithEthIsFlawed
    function testJoinGameWithEthIsFlawed() public {
        // player A creates game with token
        uint256 playerATokenBefore = token.balanceOf(playerA);

        vm.startPrank(playerA);
        token.approve(address(game), 1);
        gameId = game.createGameWithToken(TOTAL_TURNS, TIMEOUT);
        vm.stopPrank();

        uint256 playerABalanceAfter = token.balanceOf(playerA);

        assertEq(playerATokenBefore - playerABalanceAfter, 1);

        uint256 playerBBalanceBefore = token.balanceOf(playerB);

        vm.startPrank(playerB);
        game.joinGameWithEth{value: 0}(gameId);
        vm.stopPrank();
        
        uint256 playerBBalanceAfter = token.balanceOf(playerB);

        assertEq(playerBBalanceAfter, playerBBalanceBefore);

        (address storedPlayerA, address storedPlayerB,,,,,,,,,,,,,, RockPaperScissors.GameState state) =
            game.games(gameId);

        assertEq(storedPlayerA, playerA);
        assertEq(storedPlayerB, playerB);
    }

    function testJoinGameWithEthMalicious() public {
        // Create a game
        vm.prank(playerA);
        playerAInitialBalance = playerA.balance;
        contractInitialBalance = address(game).balance;
        console.log("PlayerA Initial Balance: ", playerAInitialBalance);
        console.log("Amount initially in game contract: ", contractInitialBalance);
        gameId = game.createGameWithEth{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Player B joins the game
        vm.startPrank(playerB);
        vm.expectEmit(true, true, false, true);
        playerBInitialBalance = playerB.balance;
        console.log("PlayerB Initial Balance: ", playerBInitialBalance);
        emit PlayerJoined(gameId, playerB);

        game.joinGameWithEth{value: BET_AMOUNT}(gameId);
        vm.stopPrank();

        // Player C joins the game, replacing original Player B
        vm.startPrank(playerC);
        vm.expectEmit(true, true, false, true);
        playerCInitialBalance = playerC.balance;
        console.log("PlayerC Initial Balance: ", playerCInitialBalance);
        emit PlayerJoined(gameId, playerC);

        game.joinGameWithEth{value: BET_AMOUNT}(gameId);
        vm.stopPrank();

        // Check amount in contract
        contractNewBalance = address(game).balance;
        console.log("Amount in game contract after player B leaves and player C joins: ", contractNewBalance);

        // Verify game state
        (address storedPlayerA, address storedPlayerB,,,,,,,,,,,,,, RockPaperScissors.GameState state) =
            game.games(gameId);

        // Player A cancels game to issue refund, but player B is not refunded
        vm.startPrank(playerA);
        game.cancelGame(gameId);
        playerANewBalance = playerA.balance;
        playerCNewBalance = playerC.balance;
        playerBNewBalance = playerB.balance;
        contractFinalBalance = address(game).balance;
        console.log("playerA Final Balance: ", playerANewBalance);
        console.log("playerC Final Balance: ", playerCNewBalance);
        console.log("playerB Final Balance: ", playerBNewBalance);
        console.log("Amount in game contract after game canceled: ", contractFinalBalance);
        vm.stopPrank();

        vm.startPrank(admin);
        game.withdrawFees(contractFinalBalance);

        // Assertions
        assertEq(playerANewBalance, playerAInitialBalance, "Player A not refunded");
        assertEq(playerBNewBalance, playerBInitialBalance, "Player B not refunded"); // Does not pass
        assertEq(playerCNewBalance, playerCInitialBalance, "Player C not refunded");

        assertEq(contractFinalBalance, 0, "Contract balance not zero after game canceled"); // Does not pass

        assertEq(storedPlayerA, playerA, "Final player A address is not original address");
        assertEq(storedPlayerB, playerB, "Final player B address is not original address"); // Does not pass
    }

    // ==================== GAME CREATION TESTS ====================

    // Test creating a game with ETH
    function testCreateGameWithEth() public {
        vm.startPrank(playerA);

        // Create a game with ETH
        vm.expectEmit(true, true, false, true);
        emit GameCreated(0, playerA, BET_AMOUNT, TOTAL_TURNS);

        gameId = game.createGameWithEth{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);
        vm.stopPrank();

        // Verify game details
        (
            address storedPlayerA,
            address storedPlayerB,
            uint256 bet,
            uint256 timeoutInterval,
            ,
            ,
            ,
            uint256 totalTurns,
            uint256 currentTurn,
            ,
            ,
            ,
            ,
            ,
            ,
            RockPaperScissors.GameState state
        ) = game.games(gameId);

        assertEq(storedPlayerA, playerA);
        assertEq(storedPlayerB, address(0));
        assertEq(bet, BET_AMOUNT);
        assertEq(timeoutInterval, TIMEOUT);
        assertEq(totalTurns, TOTAL_TURNS);
        assertEq(currentTurn, 1);
        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Created));
    }

    // Test creating a game with an invalid number of turns
    function test_RevertWhen_CreateGameWithEvenTurns() public {
        vm.startPrank(playerA);
        // Should fail because turns must be odd
        vm.expectRevert("Total turns must be odd");
        game.createGameWithEth{value: BET_AMOUNT}(2, TIMEOUT);
        vm.stopPrank();
    }

    // Test creating a game with too small bet
    function test_RevertWhen_CreateGameWithSmallBet() public {
        vm.startPrank(playerA);
        // Should fail because bet is too small
        vm.expectRevert("Bet amount too small");
        game.createGameWithEth{value: 0.001 ether}(TOTAL_TURNS, TIMEOUT);
        vm.stopPrank();
    }

    // Test creating a game with token
    function testCreateGameWithToken() public {
        vm.startPrank(playerA);

        // Approve token transfer
        token.approve(address(game), 1);

        // Create a game with token
        vm.expectEmit(true, true, false, true);
        emit GameCreated(0, playerA, 0, TOTAL_TURNS);

        gameId = game.createGameWithToken(TOTAL_TURNS, TIMEOUT);
        vm.stopPrank();

        // Verify token transfer
        assertEq(token.balanceOf(playerA), 9);
        assertEq(token.balanceOf(address(game)), 1);

        // Verify game details
        (address storedPlayerA,,,,,,,,,,,,,,, RockPaperScissors.GameState state) = game.games(gameId);

        assertEq(storedPlayerA, playerA);
        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Created));
    }

    // ==================== GAME JOINING TESTS ====================

    // Test joining a game with ETH
    function testJoinGameWithEth() public {
        // First create a game
        vm.prank(playerA);
        gameId = game.createGameWithEth{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Now join the game
        vm.startPrank(playerB);
        vm.expectEmit(true, true, false, true);
        emit PlayerJoined(gameId, playerB);

        game.joinGameWithEth{value: BET_AMOUNT}(gameId);
        vm.stopPrank();

        // Verify game state
        (address storedPlayerA, address storedPlayerB,,,,,,,,,,,,,, RockPaperScissors.GameState state) =
            game.games(gameId);

        assertEq(storedPlayerA, playerA);
        assertEq(storedPlayerB, playerB);
        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Created));
    }

    // Test joining a game with wrong bet amount
    function test_RevertWhen_JoinGameWithWrongBet() public {
        // First create a game
        vm.prank(playerA);
        gameId = game.createGameWithEth{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Try to join with wrong bet amount
        vm.prank(playerB);
        vm.expectRevert("Bet amount must match creator's bet");
        game.joinGameWithEth{value: BET_AMOUNT + 0.1 ether}(gameId);
    }

    // Test joining your own game
    function test_RevertWhen_JoinOwnGame() public {
        // First create a game
        vm.prank(playerA);
        gameId = game.createGameWithEth{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Try to join own game
        vm.prank(playerA);
        vm.expectRevert("Cannot join your own game");
        game.joinGameWithEth{value: BET_AMOUNT}(gameId);
    }

    // Test joining a game with token
    function testJoinGameWithToken() public {
        // First create a game with token
        vm.startPrank(playerA);
        token.approve(address(game), 1);
        gameId = game.createGameWithToken(TOTAL_TURNS, TIMEOUT);
        vm.stopPrank();

        // Now join the game with token
        vm.startPrank(playerB);
        token.approve(address(game), 1);

        vm.expectEmit(true, true, false, true);
        emit PlayerJoined(gameId, playerB);

        game.joinGameWithToken(gameId);
        vm.stopPrank();

        // Verify token transfer
        assertEq(token.balanceOf(playerB), 9);
        assertEq(token.balanceOf(address(game)), 2);

        // Verify game state
        (address storedPlayerA, address storedPlayerB,,,,,,,,,,,,,, RockPaperScissors.GameState state) =
            game.games(gameId);

        assertEq(storedPlayerA, playerA);
        assertEq(storedPlayerB, playerB);
        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Created));
    }

    // ==================== GAMEPLAY TESTS ====================

    // Helper function to create and join a game
    function createAndJoinGame() internal returns (uint256) {
        vm.prank(playerA);
        uint256 id = game.createGameWithEth{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        vm.prank(playerB);
        game.joinGameWithEth{value: BET_AMOUNT}(id);

        return id;
    }

    // Test committing moves
    function testCommitMoves() public {
        gameId = createAndJoinGame();

        // Player A commits
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        vm.expectEmit(true, true, false, true);
        emit MoveCommitted(gameId, playerA, 1);
        game.commitMove(gameId, commitA);

        // Player B commits
        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        vm.expectEmit(true, true, false, true);
        emit MoveCommitted(gameId, playerB, 1);
        game.commitMove(gameId, commitB);

        // Verify game state
        (,,,,,,,,, bytes32 storedCommitA, bytes32 storedCommitB,,,,, RockPaperScissors.GameState state) =
            game.games(gameId);

        assertEq(storedCommitA, commitA);
        assertEq(storedCommitB, commitB);
        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Committed));
    }

    // Test revealing moves
    function testRevealMoves() public {
        gameId = createAndJoinGame();

        // Commit moves
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        game.commitMove(gameId, commitB);

        // Reveal moves
        vm.prank(playerA);
        vm.expectEmit(true, true, false, true);
        emit MoveRevealed(gameId, playerA, RockPaperScissors.Move.Rock, 1);
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Rock), saltA);

        vm.prank(playerB);
        vm.expectEmit(true, true, false, true);
        emit MoveRevealed(gameId, playerB, RockPaperScissors.Move.Paper, 1);
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Paper), saltB);

        // Verify game state - after both reveals, should be ready for next turn
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 currentTurn,
            ,
            ,
            RockPaperScissors.Move moveA,
            RockPaperScissors.Move moveB,
            uint8 scoreA,
            uint8 scoreB,
            RockPaperScissors.GameState state
        ) = game.games(gameId);

        // Paper beats rock, so Player B should have 1 point
        assertEq(uint256(moveA), uint256(RockPaperScissors.Move.None)); // Moves reset for next turn
        assertEq(uint256(moveB), uint256(RockPaperScissors.Move.None));
        assertEq(scoreA, 0);
        assertEq(scoreB, 1);
        assertEq(currentTurn, 2); // Advanced to turn 2
        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Committed));
    }

    // Helper function to play a single turn
    function playTurn(uint256 _gameId, RockPaperScissors.Move moveA, RockPaperScissors.Move moveB) internal {
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A", _gameId, uint8(moveA)));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(moveA), saltA));

        vm.prank(playerA);
        game.commitMove(_gameId, commitA);

        bytes32 saltB = keccak256(abi.encodePacked("salt for player B", _gameId, uint8(moveB)));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(moveB), saltB));

        vm.prank(playerB);
        game.commitMove(_gameId, commitB);

        vm.prank(playerA);
        game.revealMove(_gameId, uint8(moveA), saltA);

        vm.prank(playerB);
        game.revealMove(_gameId, uint8(moveB), saltB);
    }

    // Test a complete game with player B winning
    function testCompleteGamePlayerBWins() public {
        gameId = createAndJoinGame();

        // First turn: A=Rock, B=Paper (B wins)
        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Paper);

        // Second turn: A=Scissors, B=Rock (B wins)
        playTurn(gameId, RockPaperScissors.Move.Scissors, RockPaperScissors.Move.Rock);

        // Third turn: A=Paper, B=Scissors (B wins)
        // This should end the game
        uint256 playerBBalanceBefore = playerB.balance;

        playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Scissors);

        // Verify game state
        (,,,,,,,,,,,,,,, RockPaperScissors.GameState state) = game.games(gameId);

        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Finished));

        // Verify player B received prize
        uint256 expectedPrize = (BET_AMOUNT * 2) * 90 / 100; // 10% fee
        assertEq(playerB.balance - playerBBalanceBefore, expectedPrize);

        // Verify player B received a winner token
        assertEq(token.balanceOf(playerB), 11);
    }

    // Test a game with player A winning
    function testCompleteGamePlayerAWins() public {
        gameId = createAndJoinGame();

        // First turn: A=Paper, B=Rock (A wins)
        playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Rock);

        // Second turn: A=Rock, B=Scissors (A wins)
        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Scissors);

        // Check state before final turn
        (,,,,,,,,,,,,, uint8 scoreA, uint8 scoreB,) = game.games(gameId);

        assertEq(scoreA, 2);
        assertEq(scoreB, 0);

        // Third turn (doesn't matter who wins, A already has majority)
        uint256 playerABalanceBefore = playerA.balance;

        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Rock);

        // Verify player A received prize
        uint256 expectedPrize = (BET_AMOUNT * 2) * 90 / 100; // 10% fee
        assertEq(playerA.balance - playerABalanceBefore, expectedPrize);
    }

    // ==================== TIMEOUT TESTS ====================

    // Test timeout join
    function testTimeoutJoin() public {
        // Create a game
        vm.prank(playerA);
        gameId = game.createGameWithEth{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Fast forward past join deadline
        vm.warp(block.timestamp + game.joinTimeout() + 1);

        // Check if can timeout
        bool canTimeout = game.canTimeoutJoin(gameId);
        assertTrue(canTimeout);

        // Execute timeout
        vm.prank(playerB); // Any address can trigger timeout
        vm.expectEmit(true, false, false, true);
        emit GameCancelled(gameId);
        game.timeoutJoin(gameId);

        // Verify game state
        (,,,,,,,,,,,,,,, RockPaperScissors.GameState state) = game.games(gameId);

        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Cancelled));

        // Verify refund
        uint256 contractBalance = address(game).balance;
        assertEq(contractBalance, 0); // All ETH returned
    }

    // Test reveal timeout with one player revealing
    function testTimeoutRevealOnePlayerRevealed() public {
        gameId = createAndJoinGame();

        // Player A commits
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        // Player B commits
        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        game.commitMove(gameId, commitB);

        // Only player A reveals
        vm.prank(playerA);
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Rock), saltA);

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + TIMEOUT + 1);

        // Check if can timeout
        (bool canTimeout, address winnerIfTimeout) = game.canTimeoutReveal(gameId);
        assertTrue(canTimeout);
        assertEq(winnerIfTimeout, playerA);

        // Execute timeout - player A should win
        uint256 playerABalanceBefore = playerA.balance;

        vm.prank(playerA);
        game.timeoutReveal(gameId);

        // Verify game state
        (,,,,,,,,,,,,,,, RockPaperScissors.GameState state) = game.games(gameId);

        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Finished));

        // Verify player A received prize
        uint256 expectedPrize = (BET_AMOUNT * 2) * 90 / 100; // 10% fee
        assertEq(playerA.balance - playerABalanceBefore, expectedPrize);
    }

    // Test reveal timeout with neither player revealing
    function testTimeoutRevealNoReveals() public {
        gameId = createAndJoinGame();

        // Both players commit
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        game.commitMove(gameId, commitB);

        // No one reveals

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + TIMEOUT + 1);

        // Check if can timeout
        (bool canTimeout, address winnerIfTimeout) = game.canTimeoutReveal(gameId);
        assertTrue(canTimeout);
        assertEq(winnerIfTimeout, address(0)); // No winner

        // Execute timeout - game should be cancelled
        uint256 playerABalanceBefore = playerA.balance;
        uint256 playerBBalanceBefore = playerB.balance;

        vm.prank(playerA);
        game.timeoutReveal(gameId);

        // Verify game state
        (,,,,,,,,,,,,,,, RockPaperScissors.GameState state) = game.games(gameId);

        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Cancelled));

        // Verify both players received refunds
        assertEq(playerA.balance - playerABalanceBefore, BET_AMOUNT);
        assertEq(playerB.balance - playerBBalanceBefore, BET_AMOUNT);
    }

    // ==================== ADMIN TESTS ====================

    // Test setting join timeout
    function testSetJoinTimeout() public {
        uint256 newTimeout = 48 hours;

        vm.expectEmit(true, false, false, true);
        emit JoinTimeoutUpdated(game.joinTimeout(), newTimeout);

        game.setJoinTimeout(newTimeout);

        assertEq(game.joinTimeout(), newTimeout);
    }

    // Test setting join timeout as non-admin
    function test_RevertWhen_SetJoinTimeoutNonAdmin() public {
        uint256 newTimeout = 48 hours;

        vm.prank(playerA);
        vm.expectRevert("Only owner can set timeout");
        game.setJoinTimeout(newTimeout);
    }

    // Test setting new admin
    function testSetAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        game.setAdmin(newAdmin);

        assertEq(game.adminAddress(), newAdmin);
    }

    // Test setting admin as non-admin
    function test_RevertWhen_SetAdminNonAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        vm.prank(playerA);
        vm.expectRevert("Only admin can set new admin");
        game.setAdmin(newAdmin);
    }

    // Test withdrawing fees
    function testWithdrawFees() public {
        // First create and complete a game to generate fees
        gameId = createAndJoinGame();

        // Play a full game to generate fees
        playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Rock);

        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Scissors);

        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Rock);

        // Calculate expected fees
        uint256 totalBet = BET_AMOUNT * 2;
        uint256 expectedFees = (totalBet * 10) / 100; // 10% fee

        // Verify accumulated fees
        assertEq(game.accumulatedFees(), expectedFees);

        // Withdraw fees
        uint256 adminBalanceBefore = address(this).balance;

        vm.expectEmit(true, false, false, true);
        emit FeeWithdrawn(address(this), expectedFees);

        game.withdrawFees(0); // 0 means withdraw all

        // Verify admin received fees
        assertEq(address(this).balance - adminBalanceBefore, expectedFees);
        assertEq(game.accumulatedFees(), 0);
    }

    // Test withdrawing specific amount of fees
    function testWithdrawSpecificFees() public {
        // First create and complete a game to generate fees
        gameId = createAndJoinGame();

        // Play a full game to generate fees
        playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Rock);

        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Scissors);

        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Rock);

        // Calculate expected fees
        uint256 totalBet = BET_AMOUNT * 2;
        uint256 expectedFees = (totalBet * 10) / 100; // 10% fee
        uint256 withdrawAmount = expectedFees / 2; // Withdraw half

        // Withdraw partial fees
        uint256 adminBalanceBefore = address(this).balance;

        game.withdrawFees(withdrawAmount);

        // Verify admin received correct amount
        assertEq(address(this).balance - adminBalanceBefore, withdrawAmount);
        assertEq(game.accumulatedFees(), expectedFees - withdrawAmount);
    }

    // Test withdrawing fees as non-admin
    function test_RevertWhen_WithdrawFeesNonAdmin() public {
        vm.prank(playerA);
        vm.expectRevert("Only admin can withdraw fees");
        game.withdrawFees(0);
    }

    // ==================== TOKEN GAME TESTS ====================

    // Helper function to create and join a token game
    function createAndJoinTokenGame() internal returns (uint256) {
        // Player A creates game with token
        vm.startPrank(playerA);
        token.approve(address(game), 1);
        uint256 id = game.createGameWithToken(TOTAL_TURNS, TIMEOUT);
        vm.stopPrank();

        // Player B joins with token
        vm.startPrank(playerB);
        token.approve(address(game), 1);
        game.joinGameWithToken(id);
        vm.stopPrank();

        return id;
    }

    // Test a complete token game
    function testCompleteTokenGame() public {
        gameId = createAndJoinTokenGame();

        // First turn: A=Paper, B=Rock (A wins)
        playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Rock);

        // Second turn: A=Rock, B=Scissors (A wins)
        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Scissors);

        // Third turn: A=Paper, B=Scissors (B wins, but A still has more points)
        uint256 tokenBalanceABefore = token.balanceOf(playerA);

        playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Scissors);

        // Verify game state
        (,,,,,,,,,,,,, uint8 scoreA, uint8 scoreB, RockPaperScissors.GameState state) = game.games(gameId);

        assertEq(scoreA, 2);
        assertEq(scoreB, 1);
        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Finished));

        // Verify winner received 2 tokens (both players' stakes)
        assertEq(token.balanceOf(playerA) - tokenBalanceABefore, 2);
    }

    // ==================== EDGE CASES ====================

    // Test cancel game by creator
    function testCancelGame() public {
        // Create a game
        vm.prank(playerA);
        gameId = game.createGameWithEth{value: BET_AMOUNT}(TOTAL_TURNS, TIMEOUT);

        // Cancel the game
        vm.prank(playerA);
        vm.expectEmit(true, false, false, true);
        emit GameCancelled(gameId);

        game.cancelGame(gameId);

        // Verify game state
        (,,,,,,,,,,,,,,, RockPaperScissors.GameState state) = game.games(gameId);

        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Cancelled));
    }

    // Test can't cancel game after someone joined
    function test_RevertWhen_CancelAfterJoin() public {
        gameId = createAndJoinGame();

        vm.prank(playerA);
        game.cancelGame(gameId);
    }

    // Test handling a tie game
    function testTieGame() public {
        // Change to 1 turn to make a tie easier to create
        vm.prank(playerA);
        gameId = game.createGameWithEth{value: BET_AMOUNT}(1, TIMEOUT);

        vm.prank(playerB);
        game.joinGameWithEth{value: BET_AMOUNT}(gameId);

        // Both players play Rock (creates a tie)
        uint256 playerABalanceBefore = playerA.balance;
        uint256 playerBBalanceBefore = playerB.balance;

        playTurn(gameId, RockPaperScissors.Move.Rock, RockPaperScissors.Move.Rock);

        // Verify game state
        (,,,,,,,,,,,,, uint8 scoreA, uint8 scoreB, RockPaperScissors.GameState state) = game.games(gameId);

        assertEq(scoreA, 0);
        assertEq(scoreB, 0);
        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Finished));

        // Verify both players received half of pot minus fees
        uint256 totalPot = BET_AMOUNT * 2;
        uint256 fee = (totalPot * 10) / 100;
        uint256 refundPerPlayer = (totalPot - fee) / 2;

        assertEq(playerA.balance - playerABalanceBefore, refundPerPlayer);
        assertEq(playerB.balance - playerBBalanceBefore, refundPerPlayer);
    }

    // Test trying to commit to a non-existent game
    function test_RevertWhen_CommitToNonExistentGame() public {
        uint256 nonExistentGameId = 9999;

        vm.prank(playerA);
        vm.expectRevert("Not a player in this game"); // Add this line to expect the specific error
        game.commitMove(nonExistentGameId, bytes32("fake commit"));
    }

    // Test trying to reveal with wrong salt
    function test_RevertWhen_RevealWrongSalt() public {
        gameId = createAndJoinGame();

        // Player A commits
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        // Player B commits
        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        game.commitMove(gameId, commitB);

        // Player A tries to reveal with wrong salt
        bytes32 wrongSalt = keccak256(abi.encodePacked("wrong salt"));

        vm.prank(playerA);
        // Add the expectRevert line to tell the test to expect this error
        vm.expectRevert("Hash doesn't match commitment");
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Rock), wrongSalt);
    }

    // Test invalid move number (outside 1-3 range)
    // Test invalid move number (outside 1-3 range)
    function test_RevertWhen_InvalidMoveNumber() public {
        gameId = createAndJoinGame();

        // Player A commits
        bytes32 saltA = keccak256(abi.encodePacked("salt for player A"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(4), saltA)); // Invalid move value

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        // Player B commits
        bytes32 saltB = keccak256(abi.encodePacked("salt for player B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        game.commitMove(gameId, commitB);

        // Player A tries to reveal an invalid move (4)
        vm.prank(playerA);

        // Add this line to expect the revert with specific error message
        vm.expectRevert("Invalid move");

        game.revealMove(gameId, 4, saltA);
    }

    // Test multi-turn game timeout functionality
    function testMultiTurnTimeout() public {
        // Create a 5-turn game
        vm.prank(playerA);
        gameId = game.createGameWithEth{value: BET_AMOUNT}(5, TIMEOUT);

        vm.prank(playerB);
        game.joinGameWithEth{value: BET_AMOUNT}(gameId);

        // First turn completes normally
        playTurn(gameId, RockPaperScissors.Move.Paper, RockPaperScissors.Move.Rock);

        // Second turn - player A commits and reveals, player B only commits
        bytes32 saltA = keccak256(abi.encodePacked("salt for turn 2"));
        bytes32 commitA = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Rock), saltA));

        vm.prank(playerA);
        game.commitMove(gameId, commitA);

        bytes32 saltB = keccak256(abi.encodePacked("salt for turn 2 B"));
        bytes32 commitB = keccak256(abi.encodePacked(uint8(RockPaperScissors.Move.Paper), saltB));

        vm.prank(playerB);
        game.commitMove(gameId, commitB);

        // Only player A reveals
        vm.prank(playerA);
        game.revealMove(gameId, uint8(RockPaperScissors.Move.Rock), saltA);

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + TIMEOUT + 1);

        // Player A claims timeout win - should win whole game
        uint256 playerABalanceBefore = playerA.balance;

        vm.prank(playerA);
        game.timeoutReveal(gameId);

        // Verify game state
        (,,,,,,,,,,,,,,, RockPaperScissors.GameState state) = game.games(gameId);

        assertEq(uint256(state), uint256(RockPaperScissors.GameState.Finished));

        // Verify player A received prize
        uint256 expectedPrize = (BET_AMOUNT * 2) * 90 / 100; // 10% fee
        assertEq(playerA.balance - playerABalanceBefore, expectedPrize);
    }

    // Test fallback function ability to receive ETH
    function testReceiveEth() public {
        // Send ETH directly to contract
        (bool success,) = address(game).call{value: 1 ether}("");
        assertTrue(success);

        // Verify contract balance increased
        assertEq(address(game).balance, 1 ether);
    }

    // Test contract ownership functions
    function testOwnershipFunctions() public {
        // Check contract owner
        assertEq(game.owner(), address(this));

        // Check token owner
        assertEq(game.tokenOwner(), address(game));

        // Verify token is owned by contract
        assertEq(token.owner(), address(game));
    }

    receive() external payable {
        // Allow the test contract to receive ETH
    }
}
