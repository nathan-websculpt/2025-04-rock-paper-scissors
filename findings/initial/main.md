### [M-01] Returned value of ERC20 transferFrom function is ignored, which could lead to plays being made by non-paying players

**Description:** 

The `RockPaperScissors::createGameWithToken` and `RockPaperScissors::joinGameWithToken` functions both contain a `winningToken.transferFrom` that could silently fail.

Example: 

`winningToken.transferFrom(msg.sender, address(this), 1);`

- Found in `RockPaperScissors` [Line: 131](https://github.com/CodeHawks-Contests/2025-04-rock-paper-scissors/blob/25cf9f29c3accd96a532e416eee6198808ba5271/src/RockPaperScissors.sol#L131)
- as well as [Line: 180](https://github.com/CodeHawks-Contests/2025-04-rock-paper-scissors/blob/25cf9f29c3accd96a532e416eee6198808ba5271/src/RockPaperScissors.sol#L180)

**Impact:** 

This could result in wrongful creation of a game, without the `RockPaperScissors` contract first collecting its funds. Note how in `RockPaperScissors::createGameWithToken` -- if the call `winningToken.transferFrom` were to fail -- the game would still get created.

```javascript
        winningToken.transferFrom(msg.sender, address(this), 1);
        // ^^^ missing the return value, which should be used to determine whether or not to proceed.

        uint256 gameId = gameCounter++;

        Game storage game = games[gameId];
        game.playerA = msg.sender;
        game.bet = 0; // Zero ether bet because using token
        game.timeoutInterval = _timeoutInterval;
        game.creationTime = block.timestamp;
        game.joinDeadline = block.timestamp + joinTimeout;
        game.totalTurns = _totalTurns;
        game.currentTurn = 1;
        game.state = GameState.Created;

        emit GameCreated(gameId, msg.sender, 0, _totalTurns);

        return gameId;
```

And similarly, in `RockPaperScissors::joinGameWithToken` -- if the `.transferFrom` fails here -- the player still gets to join the game.

```javascript
        // Transfer token to contract
        winningToken.transferFrom(msg.sender, address(this), 1);
        // ^^^ missing the return value, which should be used to determine whether or not to proceed.

        game.playerB = msg.sender;
        emit PlayerJoined(_gameId, msg.sender);
```

**Recommended Mitigation:** 

Check what these `.transferFrom` calls are returning before allowing the code-logic to progress

```javascript
    (bool success,) = winningToken.transferFrom(msg.sender, address(this), 1);
    require(success, "Transfer failed");
```



### [M-02] The generic ERC20 `.transferFrom` functionality is better-provided by OpenZeppelin's `.safeTransferFrom`

**Description:** 

While `ERC20::transferFrom` does not check if the recipient is a contract or if the contract can handle the tokens (which may lead to tokens being locked if sent to incompatible contracts), OpenZeppelin's library provides an ERC20 wrapper that greatly enhances safety and usability, with the `.safeTransferFrom` function.

**Impact:** 

ERC20 `.transferFrom` functionality does not provide any checks on/for the recipient contract

**Recommended Mitigation:** 

Swapping to OpenZeppelin's `.safeTransferFrom` will ensure that the recipient can receive the funds. 

Relating to M-01, ensure that you are checking the return of `.safeTransferFrom` to know whether or not code-logic can continue.



### L-01: Solidity pragma should be specific, not wide

Consider using a specific version of Solidity in your contracts instead of a wide version. For example, instead of `pragma solidity ^0.8.13;`, use `pragma solidity 0.8.13;`

- Found in `RockPaperScissors` [Line: 2](https://github.com/CodeHawks-Contests/2025-04-rock-paper-scissors/blob/25cf9f29c3accd96a532e416eee6198808ba5271/src/RockPaperScissors.sol#L2)
- as well as `WinningToken` [Line: 2](https://github.com/CodeHawks-Contests/2025-04-rock-paper-scissors/blob/25cf9f29c3accd96a532e416eee6198808ba5271/src/WinningToken.sol#L2)

```javascript
pragma solidity ^0.8.13;
```

### [L-02] The Timeout Reveal must extend past the game's Reveal Deadline, causing a delay

**Description:** 

- Found in `RockPaperScissors` [Line: 267](https://github.com/CodeHawks-Contests/2025-04-rock-paper-scissors/blob/25cf9f29c3accd96a532e416eee6198808ba5271/src/RockPaperScissors.sol#L267)

Notice how the `require` statement makes the player wait until the `block.timestamp` is *greater than* the `game.revealDeadline`

```javascript
require(block.timestamp > game.revealDeadline, "Reveal phase not timed out yet");
```

**Impact:** 

This is inconsistent with the timing of the rest of the game (as it relates to `game.revealDeadline`); elsewhere, comparisons are done such that they are inclusive of the value

```javascript
require(block.timestamp <= game.revealDeadline, "Reveal phase timed out");
```

**Recommended Mitigation:** 

This logic (of `RockPaperScissors` line 267) should simply be changed from a `>` comparison to a `>=` comparison 

```javascript
require(block.timestamp >= game.revealDeadline, "Reveal phase not timed out yet");
```

This will allow a player to properly utilize `RockPaperScissors::timeoutReveal` in the appropriate amount of time, rather than affording their opponent extra time.