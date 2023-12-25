# Av1an Command Generator

A tool for easily generating Av1an commands for AV1 encoding. Written in Zig.

## Description

This program generates an AV1 video encoding command for use with [Av1an](https://github.com/master-of-zen/Av1an), a chunked AV1 encoding tool for use with [aomenc](https://aomedia.googlesource.com/aom/), [SVT-AV1](https://gitlab.com/AOMediaCodec/SVT-AV1/), and [rav1e](https://github.com/xiph/rav1e). 

This tool takes in the video resolution, frame rate, desired encoder, speed preset, and target bitrate range as command line arguments. Based on these parameters, it calculates settings like tile columns/rows, lag-in-frames, CRF, and encoder speed preset. Then, it injects these into a generated encoding command string.

The output is a full `av1an` command that can be run to encode a video based on the specified settings.

## Usage

```bash
av1an-command-gen [width] [height] [fps] [encoder] [speed] [bitrate_target]
```

- `width` - Input video width in pixels 
- `height` - Input video height in pixels
- `fps` - Input video frame rate
- `encoder` - `aom`, `svt`, or `rav1e`
- `speed` - `slower`, `slow`, `med`, `fast`, `faster` 
- `bitrate_target` - `lowest`, `low`, `med`, `high`

## Examples

Generate a command for encoding a 1280x720 video at 24 fps using rav1e at 'med' speed and 'low' bitrate target:

```bash
av1an-command-gen 1280 720 24 rav1e med low
```

Generate a command for encoding a 1920x1080 video at 30 fps using svt-av1 at 'fast' speed and 'high' bitrate target:

```bash
av1an-command-gen 1920 1080 30 svt fast high
```

## Building

This program requires the [Zig](https://ziglang.org/) v0.11.0 programming language. 

To build:

```bash
zig build
```

This will produce a standalone binary `av1an-command-gen` in `zig-out/bin/`.

## Contributing

Contributions are welcome! Please open an issue or pull request on GitHub.

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.