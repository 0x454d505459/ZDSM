const std = @import("std");
const zap = @import("zap");
const oss = @import("os-stats");

const os = std.os;
const print = std.debug.print;
const mem = std.mem;
const fmt = std.fmt;
const json = std.json;

const CPUInfo = oss.CPUInfo;
const RAMStat = oss.RAMStat;
const OSInfo = oss.OSInfo;

const str = []const u8;
const DEFAULT_PORT = 3040;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var alloc = gpa.allocator();

// TODO: Parse build.zig.zon at compile time to get version
const SERVER_VERSION = "v0.0.0";

const SoftwareInfo = struct { version: str = SERVER_VERSION };

const ServerInfo = struct {
    id: str,
    uptime: i64,
    hostname: str,
    cpu: ?CPUInfo,
    ram: ?RAMStat,
    os: ?OSInfo,
};

const Infos = struct { software: SoftwareInfo, server: ServerInfo };

fn getLoadAverage() str {
    // https://fr.wikipedia.org/wiki/Load_average
    return "TODO";
}

fn trimZerosRight(value: *[64:0]u8) []u8 {
    return value[0..mem.indexOfScalar(u8, value, 0).?];
}

fn processRequest(request: zap.Request) void {
    if (!(request.method == null) and !mem.eql(u8, request.method.?, "GET") or (!(request.path == null) and !mem.eql(u8, request.path.?, "/api"))) {
        request.setStatus(.not_found);
        request.sendJson("{\"Error\":\"BAD REQUEST\"}") catch return;
        return;
    }

    // looks like getHeader is broken on this version of zap
    // const auth_header = request.getHeader("Authorization");
    // if (auth_header == null or !mem.eql(u8, auth_header.?, os.getenv("PASSWORD").?)) {
    //     request.setStatus(.forbidden);
    //     print("{?u}", .{auth_header});
    //     print("{any}", .{request});
    //     request.sendJson("{\"Error\":\"UNAUTHORIZED\"}") catch return;
    //     return;
    // }

    var request_body: []const u8 = undefined;
    var cpu_info_buff: [256]u8 = undefined;
    var uname = os.uname();

    const system_info = Infos{
        .software = SoftwareInfo{},
        .server = ServerInfo{
            .id = os.getenv("SERVER_NAME") orelse "Unnamed server",
            .uptime = oss.getUptime(),
            .hostname = trimZerosRight(&uname.nodename),
            .cpu = CPUInfo{
                .usage = oss.getCPUPercent(null) orelse 0,
                .arch = trimZerosRight(&uname.machine),
                .model = oss.parseProcInfo("/proc/cpuinfo", "model name", &cpu_info_buff, null) orelse "Unable to query CPU Name",
            },
            .ram = oss.getRAMStats(),
            .os = OSInfo{
                .type = trimZerosRight(&uname.sysname),
                .platform = trimZerosRight(&uname.sysname), // basically the same as the OS type
                .version = trimZerosRight(&uname.version),
                .release = trimZerosRight(&uname.release),
            },
        },
    };

    request_body = json.stringifyAlloc(alloc, system_info, .{}) catch "{\"Error\":\"Unable to generate JSON\"}";
    request.sendJson(request_body) catch return;
}

pub fn main() !void {
    const port = p: {
        const env = os.getenv("PORT");
        if (env == null) break :p DEFAULT_PORT;
        break :p fmt.parseUnsigned(usize, env.?, 10) catch DEFAULT_PORT;
    };
    var server = zap.HttpListener.init(.{
        .port = port,
        .on_request = processRequest,
        .log = false,
    });

    try server.listen();
    print("Started on port {any}\n", .{@as(u16, @truncate(port))});

    zap.start(.{
        .threads = 1,
        .workers = 1,
    });
}
