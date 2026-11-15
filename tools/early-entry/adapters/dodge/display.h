/* SPDX-License-Identifier: GPL-2.0-only */
/* Explicit inherited scanout contract for this device adapter.
 * This is not a descriptor exported by ABL or a generic device-name fallback. */
#ifndef DODGE_DISPLAY_H
#define DODGE_DISPLAY_H
static int dodge_display_matches(const struct eg_handoff *h)
{
    static const char model[]="Qualcomm Technologies, Inc. Sun MTP,dodge";
    static const char compat[]="qcom,sun-mtp\0qcom,sun\0qcom,sunp-mtp\0qcom,sunp\0qcom,mtp";
    static const unsigned char board[]={0,4,0,8,0,0,0,0};
    static const char key[]="msm_drm.dsi_display0=";
    static const char panel[]="msm_drm.dsi_display0=qcom,mdss_dsi_panel_AA569_P_3_A0019_dsc_cmd:PanelID-0x035E7601:PanelSN-0x";
    unsigned found=0;
    if(!dodge_bytes(h->model,h->model_len,model,sizeof(model)) ||
       !dodge_bytes(h->compatible,h->compatible_len,compat,sizeof(compat)) ||
       !dodge_bytes(h->board_id,h->board_id_len,(const char *)board,sizeof(board))) return 0;
    for(size_t i=0;i<h->bootargs_len;) {
        size_t start=i; while(i<h->bootargs_len && h->bootargs[i]!=' ') i++;
        size_t n=i-start;
        if(n>=sizeof(key)-1 && dodge_bytes(h->bootargs+start,sizeof(key)-1,key,sizeof(key)-1)) {
            if(found++ || n!=sizeof(panel)-1+16+1 ||
               !dodge_bytes(h->bootargs+start,sizeof(panel)-1,panel,sizeof(panel)-1) ||
               h->bootargs[i-1]!=':') return 0;
            for(size_t j=start+sizeof(panel)-1;j<i-1;j++) {
                unsigned c=h->bootargs[j];
                if(!((c>='0' && c<='9') || (c>='a' && c<='f') || (c>='A' && c<='F'))) return 0;
            }
        }
        if(i<h->bootargs_len) i++;
    }
    return found==1;
}
static inline struct eg_display_profile dodge_display_profile(void)
{
    struct eg_display_profile d={
    .fb={.base=0xfc800000ULL,.size=0x1167000ULL,.width=1440,.height=3168,.stride=5760,.rgb32=1},
    .reservation={0xfc800000ULL,0x2b00000ULL},
    .reservation_name="splash_region",.matches=dodge_display_matches
};
    return d;
}
#endif
