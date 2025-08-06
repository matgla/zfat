const std = @import("std");

fn bad_config(comptime fmt: []const u8, args: anytype) noreturn {
    std.debug.print(fmt ++ "\n", args);
    std.process.exit(1);
}

pub fn build(b: *std.Build) void {
    // targets:

    const demo_step = b.step("demo", "Builds the demo:");

    // options:

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const link_libc = !(b.option(bool, "no-libc", "Prevents linking of libc by default") orelse false);
    std.debug.print("Link libc: {}", .{link_libc});

    const config = blk: {
        var config = Config{};

        add_config_option(b, &config, .read_only, "If set, the library will only be able to read filesystems.");
        add_config_option(b, &config, .minimize, "Set this to different values to reduce API surface");
        add_config_option(b, &config, .find, "Enable find support");
        add_config_option(b, &config, .mkfs, "Enable mkfs support");
        add_config_option(b, &config, .fastseek, "Use fast seek option");
        add_config_option(b, &config, .expand, "Enables expandfs support");
        add_config_option(b, &config, .chmod, "Enables chmod support");
        add_config_option(b, &config, .label, "Enables support for handling of filesystem labels");
        add_config_option(b, &config, .forward, "Enables forward support");
        add_config_option(b, &config, .strfuncs, "Enables file string functions");
        add_config_option(b, &config, .printf_lli, "Enables printf_lli support");
        add_config_option(b, &config, .printf_float, "Enables printf_float support");
        add_config_option(b, &config, .strf_encoding, "Sets the format string encoding");
        add_config_option(b, &config, .max_long_name_len, "Sets the maximum name for long file names");
        add_config_option(b, &config, .code_page, "Defines the OEM code page");
        add_config_option(b, &config, .long_file_name, "Enables long file name support");
        add_config_option(b, &config, .long_file_name_encoding, "Sets the encoding for long file names");
        add_config_option(b, &config, .long_file_name_buffer_size, "Sets the buffer size for long file names");
        add_config_option(b, &config, .short_file_name_buffer_size, "Sets the buffer size for short file names");
        add_config_option(b, &config, .relative_path_api, "Enables the relative path API");
        add_config_option(b, &config, .multi_partition, "Enables support for several partitions on the same drive");
        add_config_option(b, &config, .lba64, "Enables support for 64 bit linear block addresses.");
        add_config_option(b, &config, .min_gpt_sectors, "Sector count threshold for switching to GPT partition tables");
        add_config_option(b, &config, .use_trim, "Enables support for ATA TRIM command");
        add_config_option(b, &config, .tiny, "Enable tiny buffer configuration");
        add_config_option(b, &config, .exfat, "Enables support for ExFAT");
        add_config_option(b, &config, .filesystem_trust, "Sets which values in the FSINFO structure you trust.");
        add_config_option(b, &config, .lock, "Enables file system locking");
        add_config_option(b, &config, .reentrant, "Makes the library reentrant");
        add_config_option(b, &config, .sync_type, "Defines the name of the C type which is used for sync operations");
        add_config_option(b, &config, .timeout, "Defines the timeout period in OS ticks");

        const maybe_rtc_time = b.option([]const u8, "static-rtc", "Disables runtime time API by setting the clock to a fixed value. Provide a string in the format YYYY-MM-DD");
        if (maybe_rtc_time) |rtc_time| {
            const rtc_config = time: {
                if (rtc_time.len != 10)
                    break :time null;

                if ((rtc_time[4] != '-') or (rtc_time[7] != '-'))
                    break :time null;

                const year = std.fmt.parseInt(u16, rtc_time[0..4], 10) catch break :time null;
                const month = std.fmt.parseInt(u8, rtc_time[5..7], 10) catch break :time null;
                const day = std.fmt.parseInt(u8, rtc_time[8..10], 10) catch break :time null;

                break :time RtcConfig{
                    .static = .{
                        .year = year,
                        .month = std.meta.intToEnum(std.time.epoch.Month, month) catch break :time null,
                        .day = day,
                    },
                };
            };

            config.rtc = rtc_config orelse bad_config(
                "Invalid time format. Expected YYYY-MM-DD!",
                .{},
            );
        }

        const maybe_volume_count = b.option(u5, "volume-count", "Sets the total number of volumes. Mutually exclusive with -Dvolume-names");
        const maybe_volume_names = b.option([]const u8, "volume-names", "Sets the comma separated list of volume names. Mutually exclusive with -Dvolume-count");
        if ((maybe_volume_count != null) and (maybe_volume_names != null)) {
            bad_config("-Dvolume-count and -Dvolume-names are mutually exclusive.", .{});
        }

        if (maybe_volume_count) |volume_count| {
            config.volumes = .{ .count = volume_count };
        }

        if (maybe_volume_names) |volume_names| {
            var volumes = std.ArrayList([]const u8).init(b.allocator);

            var iter = std.mem.splitScalar(u8, volume_names, ',');
            while (iter.next()) |name| {
                volumes.append(name) catch @panic("out of memory");
            }
            config.volumes = .{ .named = volumes.items };
        }

        const maybe_sector_config = b.option([]const u8, "sector-size", "Defines the sector size range. Use `<min>:<max>` or `<fixed>`. Valid items for the range are 512, 1024, 2048 or 4096. No other values allowed.");
        if (maybe_sector_config) |sector_config| {
            if (std.mem.indexOfScalar(u8, sector_config, ':')) |split| {
                const min = sector_config[0..split];
                const max = sector_config[split + 1 ..];

                config.sector_size = .{
                    .dynamic = .{
                        .minimum = std.meta.stringToEnum(SectorOption, min) orelse bad_config(
                            "Invalid value for -Dsector-size: '{f}'",
                            .{std.zig.fmtString(sector_config)},
                        ),
                        .maximum = std.meta.stringToEnum(SectorOption, max) orelse bad_config(
                            "Invalid value for -Dsector-size: '{f}'",
                            .{std.zig.fmtString(sector_config)},
                        ),
                    },
                };
            } else {
                config.sector_size = .{
                    .static = std.meta.stringToEnum(SectorOption, sector_config) orelse bad_config(
                        "Invalid value for -Dsector-size: '{f}'",
                        .{std.zig.fmtString(sector_config)},
                    ),
                };
            }
        }

        // add_config_option(b, &config, .sector_size, "");
        break :blk config;
    };

    const config_header = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "ffconf.h",
    }, .{
        .FFCONF_DEF = 5380,
    });

    switch (config.volumes) {
        .count => |count| {
            config_header.addValues(.{
                .FF_VOLUMES = count,
                .FF_STR_VOLUME_ID = 0,
            });
        },
        .named => |strings| {
            var list = std.ArrayList(u8).init(b.allocator);
            for (strings) |name| {
                if (list.items.len > 0) {
                    list.appendSlice(", ") catch @panic("out of memory");
                }
                list.writer().print("\"{X}\"", .{
                    name,
                }) catch @panic("out of memory");
            }
            config_header.addValues(.{
                .FF_VOLUMES = @as(i64, @intCast(strings.len)),
                .FF_STR_VOLUME_ID = 1,
                .FF_VOLUME_STRS = list.items,
            });
        },
    }

    switch (config.sector_size) {
        .static => |size| {
            config_header.addValues(.{
                .FF_MIN_SS = size,
                .FF_MAX_SS = size,
            });
        },
        .dynamic => |range| {
            config_header.addValues(.{
                .FF_MIN_SS = range.minimum,
                .FF_MAX_SS = range.maximum,
            });
        },
    }

    inline for (comptime std.meta.fields(Config)) |fld| {
        add_config_field(config_header, config, fld.name);
    }

    switch (config.rtc) {
        .dynamic => {
            config_header.addValue("FF_FS_NORTC", bool, false);
        },
        .static => |date| {
            config_header.addValues(.{
                .FF_FS_NORTC = 1,
                .FF_NORTC_MON = date.month.numeric(),
                .FF_NORTC_MDAY = date.day,
                .FF_NORTC_YEAR = date.year,
            });
        },
    }

    // module:
    const upstream = b.dependency("fatfs", .{});

    const mod_options = b.addOptions();
    mod_options.addOption(bool, "has_rtc", (config.rtc != .static));

    // create copy of the upstream without ffconf.h
    const upstream_copy = b.addWriteFiles();
    _ = upstream_copy.addCopyFile(upstream.path("source/ff.c"), "ff.c");
    _ = upstream_copy.addCopyFile(upstream.path("source/ff.h"), "ff.h");
    _ = upstream_copy.addCopyFile(upstream.path("source/diskio.h"), "diskio.h");
    _ = upstream_copy.addCopyFile(upstream.path("source/ffunicode.c"), "ffunicode.c");
    _ = upstream_copy.addCopyFile(upstream.path("source/ffsystem.c"), "ffsystem.c");
    const upstream_copy_dir = upstream_copy.getDirectory();

    const zfat_lib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = link_libc,
    });
    zfat_lib_mod.addCSourceFiles(.{
        .root = upstream_copy_dir,

        .files = &.{
            "ff.c",
            "ffunicode.c",
            "ffsystem.c",
        },
        .flags = &.{"-std=c99"},
    });
    zfat_lib_mod.addConfigHeader(config_header);

    const zfat = b.addLibrary(.{
        .linkage = .static,
        .name = "zfat",
        .root_module = zfat_lib_mod,
    });
    zfat.installHeader(upstream_copy_dir.path(b, "ff.h"), "ff.h");
    zfat.installHeader(upstream_copy_dir.path(b, "diskio.h"), "diskio.h");
    zfat.installConfigHeader(config_header);

    const zfat_mod = b.addModule("zfat", .{
        .root_source_file = b.path("src/fatfs.zig"),
        .target = target,
        .optimize = optimize,
    });
    zfat_mod.linkLibrary(zfat);
    zfat_mod.addOptions("config", mod_options);

    const demo_module = b.createModule(.{
        .root_source_file = b.path("demo/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // usage demo:
    const exe = b.addExecutable(.{
        .name = "zfat-demo",
        .root_module = demo_module,
    });
    exe.root_module.addImport("zfat", zfat_mod);

    const demo_exe = b.addInstallArtifact(exe, .{});
    demo_step.dependOn(&demo_exe.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn add_config_field(config_header: *std.Build.Step.ConfigHeader, config: Config, comptime field_name: []const u8) void {
    const value = @field(config, field_name);
    const Type = @TypeOf(value);
    const type_info = @typeInfo(Type);

    if (Type == VolumeKind or Type == SectorSize or Type == RtcConfig)
        return // we don't emit these automatically
    else if (type_info == .@"enum") {
        const macro_name = @field(macro_names, field_name);
        config_header.addValue(macro_name, i64, @intFromEnum(value));
    } else {
        const macro_name = @field(macro_names, field_name);
        config_header.addValue(macro_name, Type, value);
    }
}

fn add_config_option(b: *std.Build, config: *Config, comptime field: @TypeOf(.tag), desc: []const u8) void {
    const T = @FieldType(Config, @tagName(field));
    if (b.option(T, @tagName(field), desc)) |value|
        @field(config, @tagName(field)) = value;
}

pub const Config = struct {
    read_only: bool = false,
    minimize: MinimizeLevel = .default,
    find: bool = false,
    mkfs: bool = false,
    fastseek: bool = false,
    expand: bool = false,
    chmod: bool = false,
    label: bool = false,
    forward: bool = false,
    strfuncs: StringFuncConfig = .disabled,
    printf_lli: bool = false,
    printf_float: bool = false,
    strf_encoding: StrfEncoding = .oem,
    max_long_name_len: u8 = 255,
    code_page: CodePage = .us,
    long_file_name: bool = true,
    long_file_name_encoding: LfnEncoding = .oem,
    long_file_name_buffer_size: u32 = 255,
    short_file_name_buffer_size: u32 = 12,
    relative_path_api: RelativePathApi = .disabled,
    volumes: VolumeKind = .{ .count = 1 },
    sector_size: SectorSize = .{ .static = .@"512" },
    multi_partition: bool = false,
    lba64: bool = false,
    min_gpt_sectors: u32 = 0x10000000,
    use_trim: bool = false,
    tiny: bool = false,
    exfat: bool = false,
    rtc: RtcConfig = .dynamic,
    filesystem_trust: Trust = .trust_all,
    lock: u32 = 0,
    reentrant: bool = false,

    sync_type: []const u8 = "HANDLE", // default to windows
    timeout: u32 = 1000,
};

pub const Trust = enum(u2) {
    // bit0=0: Use free cluster count in the FSINFO if available.
    // bit0=1: Do not trust free cluster count in the FSINFO.
    // bit1=0: Use last allocated cluster number in the FSINFO if available.
    // bit1=1: Do not trust last allocated cluster number in the FSINFO.

    trust_all = 0,
    trust_last_sector = 0b01,
    trust_free_clusters = 0b10,
    scan_all = 0b11,
};

pub const RtcConfig = union(enum) {
    dynamic,
    static: struct {
        day: u32,
        month: std.time.epoch.Month,
        year: u32,
    },
};

pub const VolumeKind = union(enum) {
    count: u5, // 1 … 10
    named: []const []const u8,
};

pub const SectorOption = enum(u32) {
    @"512" = 512,
    @"1024" = 1024,
    @"2048" = 2048,
    @"4096" = 4096,
};

pub const SectorSize = union(enum) {
    static: SectorOption,
    dynamic: struct {
        minimum: SectorOption,
        maximum: SectorOption,
    },
};

pub const RelativePathApi = enum(u2) {
    disabled = 0,
    enabed = 1,
    enabled_with_getcwd = 2,
};

pub const LfnEncoding = enum(u2) {
    oem = 0, // ANSI/OEM in current CP (TCHAR = char)
    utf16 = 1, // Unicode in UTF-16 (TCHAR = WCHAR)
    utf8 = 2, // Unicode in UTF-8 (TCHAR = char)
    utf32 = 3, // Unicode in UTF-32 (TCHAR = DWORD)
};

pub const StrfEncoding = enum(u2) {
    oem = 0,
    utf16_le = 1,
    utf16_be = 2,
    utf8 = 3,
};

pub const StringFuncConfig = enum(u2) {
    disabled = 0,
    enabled = 1,
    enabled_with_crlf = 2,
};

pub const MinimizeLevel = enum(u2) {
    default = 0,
    no_advanced = 1,
    no_dir_iteration = 2,
    no_lseek = 3,
};

pub const CodePage = enum(c_int) {
    dynamic = 0, // Include all code pages above and configured by f_setcp()

    us = 437,
    arabic_ms = 720,
    greek = 737,
    kbl = 771,
    baltic = 775,
    latin_1 = 850,
    latin_2 = 852,
    cyrillic = 855,
    turkish = 857,
    portuguese = 860,
    icelandic = 861,
    hebrew = 862,
    canadian_french = 863,
    arabic_ibm = 864,
    nordic = 865,
    russian = 866,
    greek_2 = 869,
    japanese_dbcs = 932,
    simplified_chinese_dbcs = 936,
    korean_dbcs = 949,
    traditional_chinese_dbcs = 950,
};

const macro_names = struct {
    pub const read_only = "FF_FS_READONLY";
    pub const minimize = "FF_FS_MINIMIZE";
    pub const find = "FF_USE_FIND";
    pub const mkfs = "FF_USE_MKFS";
    pub const fastseek = "FF_USE_FASTSEEK";
    pub const expand = "FF_USE_EXPAND";
    pub const chmod = "FF_USE_CHMOD";
    pub const label = "FF_USE_LABEL";
    pub const forward = "FF_USE_FORWARD";
    pub const strfuncs = "FF_USE_STRFUNC";
    pub const printf_lli = "FF_PRINT_LLI";
    pub const printf_float = "FF_PRINT_FLOAT";
    pub const strf_encoding = "FF_STRF_ENCODE";
    pub const long_file_name = "FF_USE_LFN";
    pub const max_long_name_len = "FF_MAX_LFN";
    pub const code_page = "FF_CODE_PAGE";
    pub const long_file_name_encoding = "FF_LFN_UNICODE";
    pub const long_file_name_buffer_size = "FF_LFN_BUF";
    pub const short_file_name_buffer_size = "FF_SFN_BUF";
    pub const relative_path_api = "FF_FS_RPATH";
    pub const multi_partition = "FF_MULTI_PARTITION";
    pub const lba64 = "FF_LBA64";
    pub const min_gpt_sectors = "FF_MIN_GPT";
    pub const use_trim = "FF_USE_TRIM";
    pub const tiny = "FF_FS_TINY";
    pub const exfat = "FF_FS_EXFAT";
    pub const filesystem_trust = "FF_FS_NOFSINFO";
    pub const lock = "FF_FS_LOCK";
    pub const reentrant = "FF_FS_REENTRANT";
    pub const timeout = "FF_FS_TIMEOUT";
    pub const sync_type = "FF_SYNC_t";
};
