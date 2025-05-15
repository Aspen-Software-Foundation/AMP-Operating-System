pub const limine = @import("limine");
const kmain = @import("main").kmain;
const hcf = @import("hcf").hcf;

export var start_marker: limine.RequestsStartMarker linksection(".limine_requests_start") = .{};
export var end_marker: limine.RequestsEndMarker linksection(".limine_requests_end") = .{};

pub export var stack_request: limine.StackSizeRequest linksection(".limine_requests") = .{
    .stack_size = 64 * 1024,
};

pub export var paging_request: limine.PagingModeRequest linksection(".limine_requests") = .{};

export var base_revision: limine.BaseRevision linksection(".limine_requests") = .init(3);

pub export fn _start() callconv(.C) void {
    if (!base_revision.isSupported()) {
        hcf();
    }

    kmain();

    hcf();
}
