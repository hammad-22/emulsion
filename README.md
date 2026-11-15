# Emulsion

A free, open-source film lab for iPhone and Mac. Shoot or import RAW and log footage, and Emulsion develops it through a simulated negative → print film process instead of a filter.

- **Engine** (`EmulsionCore`): scene-referred input transforms (ProRAW, Apple Log, S-Log3, LogC, V-Log, DaVinci Intermediate, ACEScct, HLG), a photochemical negative/print model, halation, grain and halo-free local tone, all on Core Image + Metal. See [docs/ENGINE.md](docs/ENGINE.md).
- **iPhone app:** camera-first. Shoot in RAW with a film "recipe" applied non-destructively; simple editing. Designed for regular iPhones and iPhone Duo.
- **Mac app** (planned): a pro editor for colorists on the same engine.

Status: early development. The engine builds and is tested; the apps are being built.

## Build and test

Requires Xcode 26 or later on macOS 26.

```bash
cd Packages/EmulsionCore && swift test
```

## Contributing

Read [AGENTS.md](AGENTS.md) for the engineering rules (they apply to humans and coding agents alike) and [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GNU Affero General Public License v3.0 only (AGPL-3.0-only). See [LICENSE](LICENSE) and [NOTICE](NOTICE). You may use, study, change and share Emulsion; if you distribute it or a modified version, you must share your source under the same licence. For other licensing terms, contact the copyright holder.

Film stock names are trademarks of their owners; Emulsion is not affiliated with or endorsed by them.
