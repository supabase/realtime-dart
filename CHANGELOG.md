## [0.1.8]

- fix: add strict typing to `convertChangeData()`

## [0.1.7]

- fix: heartbeatTimer not cancelled upon calling `socket.disconnect()`

## [0.1.6]

- fix: getting value from received response map

## [0.1.5]

- fix: bug where unsubscribe from '\*' type subscription throws exception

## [0.1.4]

- fix: timeout timer not starting

## [0.1.3]

- refactor: rename Column class to PostgresColumn

## [0.1.2]

- fix: subscription type '\*' does not fire callback bug

## [0.1.1]

- fix: converted typedefs in `RealtimeClient` to function types

## [0.1.0]

- fix: heartbeat event name

## [0.0.9]

- fix: default reconnectAfterMs function throws RangeError
- chore: update mocktail version

## [0.0.8]

- feature: Null-Safety

## [0.0.7]

- fix: Web compatibility

## [0.0.6]

- fix: RetryTimer `_tries` is not initialized

## [0.0.5]

- fix: transformers.convertColumn method

## [0.0.4]

- fix: convertChangeData.columns type to List<Map<String, dynamic>>

## [0.0.3]

- fix: binding filter bug on realtimeSubscription trigger method

## [0.0.2]

- chore: replace `Map` with `Map<String, dyanmic>`
- tidy up

## [0.0.1]

- chore: update README
- fix: convertChangeData columns param type

## [0.0.1-dev.5]

- fix: transformers convertChangeData method

## [0.0.1-dev.4]

- Improve docs

#### BREAKING CHANGES

- Rename `socket` to `RealtimeClient`
- Rename `channel` to `RealtimeSubscription`

## [0.0.1-dev.3]

- Update README Usage with more examples
- Update package description

## [0.0.1-dev.2]

- Update README

## [0.0.1-dev.1]

- Initial pre-release.
