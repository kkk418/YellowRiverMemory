/**
 * 颜色常量：从 color.json 的资源映射为统一使用的对象
 * 使用 $r() 引用，运行时由资源系统解析
 */

class C {
  bg: ResourceColor = $r('app.color.ink_wall');
  bgElevated: ResourceColor = $r('app.color.ink_wall_elevated');
  bgCard: ResourceColor = $r('app.color.ink_wall_card');
  border: ResourceColor = $r('app.color.ink_line');
  borderSub: ResourceColor = $r('app.color.divider');
  gold: ResourceColor = $r('app.color.gold_primary');
  goldLight: ResourceColor = $r('app.color.gold_light');
  goldDim: ResourceColor = $r('app.color.gold_dim');
  gold20: ResourceColor = $r('app.color.gold_20');
  gold10: ResourceColor = $r('app.color.gold_10');
  textPrimary: ResourceColor = $r('app.color.text_primary');
  textSecondary: ResourceColor = $r('app.color.text_secondary');
  textTertiary: ResourceColor = $r('app.color.text_tertiary');
  ricePaper: ResourceColor = $r('app.color.rice_paper');
  bronzeGreen: ResourceColor = $r('app.color.bronze_green');
  cinnabar: ResourceColor = $r('app.color.vermillion');
  pottery: ResourceColor = $r('app.color.pottery_orange');
  jade: ResourceColor = $r('app.color.jade_green');
  blueWhite: ResourceColor = $r('app.color.blue_white');
  mask: ResourceColor = $r('app.color.overlay_mask');
  error: ResourceColor = $r('app.color.error_red');
  success: ResourceColor = $r('app.color.success_green');
  // 朝代色
  era_yangshao: ResourceColor = $r('app.color.era_yangshao');
  era_longshan: ResourceColor = $r('app.color.era_longshan');
  era_xiashang: ResourceColor = $r('app.color.era_xiashang');
  era_zhou: ResourceColor = $r('app.color.era_zhou');
  era_hantang: ResourceColor = $r('app.color.era_hantang');
  era_song: ResourceColor = $r('app.color.era_song');
  // 标签
  tagBg: ResourceColor = $r('app.color.tag_bg_default');
  tagText: ResourceColor = $r('app.color.tag_text_default');
  tagBgActive: ResourceColor = $r('app.color.tag_bg_selected');
  tagTextActive: ResourceColor = $r('app.color.tag_text_selected');
  tagBorderActive: ResourceColor = $r('app.color.tag_border_selected');
}

export const colors: C = new C();
