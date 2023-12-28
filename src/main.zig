const std = @import("std");
const testing = std.testing;
const parseInt = std.fmt.parseInt;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // Parse args into string array (error union needs 'try')
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Error union for negative integers
    const InputError = error{
        WrongArgCount,
        IsNegative,
        ImpEncoderTarg,
        ImpBitrateTarg,
        ImpSpeedTarg,
    };

    // Enums for bitrate target, encoder target, and speed target
    const bitrateTarget = enum(u4) { lowest, low, med, high };
    const encoderTarget = enum(u4) { aom, svt, rav1e };
    const speedTarget = enum(u4) { slower, slow, med, fast, faster };

    if (args.len == 1) { // if the user provided no args ...
        try stdout.print("Please provide at least 6 arguments.\n", .{});
        try stdout.print("Run `av1an-command-gen -h` for more info.\n", .{});
        return InputError.WrongArgCount;
    }

    if (std.mem.eql(u8, args[1], "-h")) { // if the user provided `-h` ...
        _ = try help(); // run the help function to print the help menu
        return;
    }

    // too few args
    if (args.len < 7) {
        try stdout.print("Please provide at least 6 arguments.\n", .{});
        try stdout.print("Run `av1an-command-gen -h` for more info.\n", .{});
        return InputError.WrongArgCount;
    }

    // too many args
    if (args.len > 7) {
        try stdout.print("Please provide at most 6 arguments.\n", .{});
        try stdout.print("Run `av1an-command-gen -h` for more info.\n", .{});
        return InputError.WrongArgCount;
    }

    // check if the user provided a negative integer
    var isNeg: i16 = undefined;
    for (args[1..4]) |arg| { // for every argument ...
        isNeg = try parseInt(i16, arg, 10); // parse each argument as an i16
        // if the argument is less than 0 (it is negative) ...
        if (isNeg < 0) {
            try stdout.print("Please provide positive integers.\n", .{});
            try stdout.print("Run `av1an-command-gen -h` for more info.\n", .{});
            return InputError.IsNegative;
        }
    }

    // user-provided encoder. maps to aom, svt, and rav1e
    var encoder_tgt: encoderTarget = undefined;

    if (std.mem.eql(u8, args[4], "aom")) {
        encoder_tgt = encoderTarget.aom;
    } else if (std.mem.eql(u8, args[4], "svt")) {
        encoder_tgt = encoderTarget.svt;
    } else if (std.mem.eql(u8, args[4], "rav1e")) {
        encoder_tgt = encoderTarget.rav1e;
    } else {
        try stdout.print("Please provide a proper encoder argument.\n", .{});
        return InputError.ImpEncoderTarg;
    }

    // user-provided bitrate range. maps to lowest, low, medium, and high
    var bitrate_tgt: bitrateTarget = undefined;

    if (std.mem.eql(u8, args[6], "lowest")) {
        bitrate_tgt = bitrateTarget.lowest;
    } else if (std.mem.eql(u8, args[6], "low")) {
        bitrate_tgt = bitrateTarget.low;
    } else if (std.mem.eql(u8, args[6], "med")) {
        bitrate_tgt = bitrateTarget.med;
    } else if (std.mem.eql(u8, args[6], "high")) {
        bitrate_tgt = bitrateTarget.high;
    } else {
        try stdout.print("Please provide a proper bitrate target argument.\n", .{});
        return InputError.ImpBitrateTarg;
    }

    // user-provided speed target. maps to slower, slow, med, fast, and faster
    var speed_tgt: speedTarget = undefined;

    if (std.mem.eql(u8, args[5], "slower")) {
        speed_tgt = speedTarget.slower;
    } else if (std.mem.eql(u8, args[5], "slow")) {
        speed_tgt = speedTarget.slow;
    } else if (std.mem.eql(u8, args[5], "med")) {
        speed_tgt = speedTarget.med;
    } else if (std.mem.eql(u8, args[5], "fast")) {
        speed_tgt = speedTarget.fast;
    } else if (std.mem.eql(u8, args[5], "faster")) {
        speed_tgt = speedTarget.faster;
    } else {
        try stdout.print("Please provide a proper speed target argument.\n", .{});
        return InputError.ImpSpeedTarg;
    }

    // calculate x-splits in Av1an based on user-provided fps. multiply it by 60 so it is easier to divide later
    var xs: usize = try parseInt(usize, args[3], 10);
    xs *= 60;

    // initialize the lag in frames variable
    var lif: usize = undefined;

    // initialize crf variables
    var crf_aom: u8 = undefined;
    var crf_svt: u8 = undefined;
    var q_rav1e: u8 = undefined;

    // set the x-splits & lag in frames based on the bitrate range
    switch (bitrate_tgt) {
        bitrateTarget.lowest => { // "lowest" bitrate target
            xs /= 3;
            lif = 64;
            crf_aom = 41;
            crf_svt = 40;
            q_rav1e = 120;
        },
        bitrateTarget.low => { // "low" bitrate target
            xs /= 4;
            lif = 48;
            crf_aom = 33;
            crf_svt = 32;
            q_rav1e = 100;
        },
        bitrateTarget.med => { // "medium" bitrate target
            xs /= 6;
            lif = 48;
            crf_aom = 24;
            crf_svt = 23;
            q_rav1e = 70;
        },
        bitrateTarget.high => { // "high" bitrate target
            xs /= 6;
            lif = 48;
            crf_aom = 20;
            crf_svt = 19;
            q_rav1e = 60;
        },
    }

    // Parse target width & height from the first & second args
    const width: usize = try parseInt(usize, args[1], 10);
    const height: usize = try parseInt(usize, args[2], 10);

    // Target pixels per tile (actual result will be ≥2/3 and <4/3 of this number)
    const tpx: usize = 2000000;

    // initialize rows log 2 & columns log 2
    var rowsl: usize = 0;
    var colsl: usize = 0;

    var ctpx: usize = width * height; // current tile pixels, starts at the full size of the video, we subdivide until <4/3 of tpx
    var ctar: usize = width / height; // current tile aspect ratio, we subdivide into cols if >1 and rows if ≤1

    _ = getTiles(tpx, &rowsl, &colsl, &ctpx, &ctar);

    // initialize literal columns & literal rows
    const cols: usize = std.math.pow(usize, 2, colsl);
    const rows: usize = std.math.pow(usize, 2, rowsl);

    // set encoder speed depending on user-provided encoder and speed targets
    var encoderSpeed: u4 = undefined;
    switch (speed_tgt) {
        speedTarget.slower => { // "slower" speed target
            if (encoder_tgt == encoderTarget.aom) {
                encoderSpeed = 3;
            } else if (encoder_tgt == encoderTarget.svt) {
                encoderSpeed = 2;
            } else if (encoder_tgt == encoderTarget.rav1e) {
                encoderSpeed = 3;
            }
        },
        speedTarget.slow => { // "slow" speed target
            if (encoder_tgt == encoderTarget.aom) {
                encoderSpeed = 4;
            } else if (encoder_tgt == encoderTarget.svt) {
                encoderSpeed = 4;
            } else if (encoder_tgt == encoderTarget.rav1e) {
                encoderSpeed = 4;
            }
        },
        speedTarget.med => { // "medium" speed target
            if (encoder_tgt == encoderTarget.aom) {
                encoderSpeed = 5;
            } else if (encoder_tgt == encoderTarget.svt) {
                encoderSpeed = 6;
            } else if (encoder_tgt == encoderTarget.rav1e) {
                encoderSpeed = 6;
            }
        },
        speedTarget.fast => { // "fast" speed target
            if (encoder_tgt == encoderTarget.aom) {
                encoderSpeed = 5;
            } else if (encoder_tgt == encoderTarget.svt) {
                encoderSpeed = 8;
            } else if (encoder_tgt == encoderTarget.rav1e) {
                encoderSpeed = 8;
            }
        },
        speedTarget.faster => { // "faster" speed target
            if (encoder_tgt == encoderTarget.aom) {
                encoderSpeed = 5;
            } else if (encoder_tgt == encoderTarget.svt) {
                encoderSpeed = 10;
            } else if (encoder_tgt == encoderTarget.rav1e) {
                encoderSpeed = 9;
            }
        },
    }

    // print results
    if (encoder_tgt == encoderTarget.aom) {
        try stdout.print("~~~~\n", .{});
        try stdout.print("Generated Command: ", .{});
        try stdout.print("av1an --resume -i \"INPUT.mkv\" --verbose --split-method av-scenechange -m lsmash -c mkvmerge --sc-downscale-height {d} -e aom --force -v \"--good --bit-depth=10 --tile-columns={d} --tile-rows={d} --end-usage=q --threads=2 --tune=ssim --ssim-rd-mult=125 --tune-content=psy --arnr-maxframes=15 --arnr-strength=2 --enable-cdef=0 --loopfilter-control=3 --quant-sharpness=3 --deltaq-mode=1 --aq-mode=0 --enable-keyframe-filtering=1 --luma-bias=25 --luma-bias-strength=15 --luma-bias-midpoint=66 --enable-qm=1 --quant-b-adapt=1 --lag-in-frames={d} --sb-size=dynamic --disable-kf --kf-max-dist=9999 --cpu-used={d} --cq-level={d} --denoise-noise-level=9 --enable-dnl-denoising=0\" --pix-format yuv420p10le -a \"-c:a libopus -b:a 128k -ac 2\" -x {d} --set-thread-affinity 2 -w 0 -o \"OUTPUT.mkv\"\n", .{ height, colsl, rowsl, lif, encoderSpeed, crf_aom, xs });
        try stdout.print("~~~~\n", .{});
    } else if (encoder_tgt == encoderTarget.svt) {
        try stdout.print("~~~~\n", .{});
        try stdout.print("Generated Command: ", .{});
        try stdout.print("av1an --resume -i \"INPUT.mkv\" --verbose --split-method av-scenechange -m lsmash -c mkvmerge --sc-downscale-height {d} -e svt-av1 --force -v \"--tile-rows {d} --tile-columns {d} --input-depth 10 --tune 2 --enable-overlays 1 --enable-qm 1 --qm-min 0 --qm-max 15 --keyint -1 --scd 0 --lp 1 --irefresh-type 1 --crf {d} --preset {d} --film-grain 12 --film-grain-denoise 0\" --pix-format yuv420p10le -a \"-c:a libopus -b:a 128k -ac 2\" -x {d} --set-thread-affinity 2 -w 0 -o \"OUTPUT.mkv\"\n", .{ height, rowsl, colsl, crf_svt, encoderSpeed, xs });
        try stdout.print("~~~~\n", .{});
    } else if (encoder_tgt == encoderTarget.rav1e) {
        try stdout.print("~~~~\n", .{});
        try stdout.print("Generated Command: ", .{});
        try stdout.print("av1an --resume -i \"INPUT.mkv\" --verbose --split-method av-scenechange -m lsmash -c mkvmerge --sc-downscale-height {d} -e rav1e --force -v \"--tile-rows {d} --tile-cols {d} --threads 2 --no-scene-detection -s {d} --quantizer {d} --photon-noise 13\" --pix-format yuv420p10le -a \"-c:a libopus -b:a 128k -ac 2\" -x {d} --set-thread-affinity 2 -w 0 -o \"OUTPUT.mkv\"\n", .{ height, rows, cols, encoderSpeed, q_rav1e, xs });
        try stdout.print("~~~~\n", .{});
    }
}

fn getTiles(tpx: usize, rowsl_ptr: *usize, colsl_ptr: *usize, ctpx_ptr: *usize, ctar_ptx: *usize) void {
    // NOTE: tpx = 2,000,000 results in 1 tile at 1080p, tpx = 1,000,000 results in 2 tiles at 1080p.
    // By default, tpx is set to 2,000,000. You can change this if you prefer smaller tiles, which come
    // at the cost of coding efficiency.

    // while current tile pixels >= pixels per tile * 4/3
    while (ctpx_ptr.* >= tpx * 4 / 3) {
        if (ctar_ptx.* > 1) {
            // Subdivide into columns, add 1 to colsl, halve ctar, halve ctpx
            colsl_ptr.* += 1;
            ctar_ptx.* /= 2;
            ctpx_ptr.* /= 2;
        } else {
            // Subdivide into rows, add 1 to rowsl, double ctar, halve ctpx
            rowsl_ptr.* += 1;
            ctar_ptx.* *= 2;
            ctpx_ptr.* /= 2;
        }
    }
}

fn help() !void {
    const stdout = std.io.getStdOut().writer();

    // Contains print statements for the help menu
    try stdout.print("Av1an Command Generator | AV1 Encoding Helper\n", .{});
    try stdout.print("Generates an AV1 encoding command for live-action encoding with Av1an.\n", .{});
    try stdout.print("Usage: av1an-command-gen [width] [height] [fps] [encoder] [speed] [bitrate_target]\n", .{});
    try stdout.print("\n", .{});
    try stdout.print("Options:\n", .{});
    try stdout.print("\tWidth:\t\tYour input width in pixels\n", .{});
    try stdout.print("\tHeight:\t\tYour input height in pixels\n", .{});
    try stdout.print("\tfps:\t\tYour input frames per second\n", .{});
    try stdout.print("\tEncoder:\tAccepts `aom`, `svt`, `rav1e`\n", .{});
    try stdout.print("\tSpeed:\t\tAccepts `slower`, `slow`, `med`, `fast`, `faster`\n", .{});
    try stdout.print("\tBitrate Target:\tAccepts `lowest`, `low`, `med`, `high`\n", .{});
    return;
}

// Test case for the getTiles function. Tests if the function returns the correct values.
// If you manually changed the values passed to the getTiles function, you should change the values here too.
test "getTiles" {
    var testrowsl: usize = 0;
    var testcolsl: usize = 0;

    var testctpx: usize = 1920 * 1080;
    var testctar: usize = 1920 / 1080;
    var testtpx: usize = 2000000;

    _ = getTiles(testtpx, &testrowsl, &testcolsl, &testctpx, &testctar);

    try testing.expect(testrowsl == 0);
    try testing.expect(testcolsl == 0);
}
