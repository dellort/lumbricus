module aconv.metadata;

const ANIMDESC_FLAGS_REPEAT = 0x1;
const ANIMDESC_FLAGS_BACKWARDS = 0x2;
///this flag specifies if the animation data uses the old (anim_xxx.png)
///or the new box-packed (page_xxx.png) format
///if set, MyFrameDescriptorBoxPacked is used to describe each frame,
///else MyFrameDescriptor is used
const ANIMDESC_FLAGS_BOXPACKED = 0x4;

struct MyAnimationDescriptor {
align(1):
    short framecount;
    short w;
    short h;
    short flags;
}
///basic frame descriptor for old-style (one animation per file) anims
struct MyFrameDescriptor {
align(1):
    short offsetx;
    short offsety;
    short width;
    short height;
}
///extended frame descriptor for box-packed animations
struct MyFrameDescriptorBoxPacked {
align(1):
    MyFrameDescriptor fd;
    short pageIndex;
    short pageOffsetx;
    short pageOffsety;
}
