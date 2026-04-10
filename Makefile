include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-jdc-tgbot
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-jdc-tgbot
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=jdc-TGbot for Telegram + Passwall controller
  DEPENDS:=+curl +coreutils +coreutils-base64 +jq +luci-base +luci-compat +jsonfilter
  PROVIDES:=luci-app-tgpasswall
  CONFLICTS:=luci-app-tgpasswall
endef

define Package/luci-app-jdc-tgbot/description
 Telegram Bot control bridge for OpenWrt system status and luci-app-passwall operations.
endef

define Build/Compile
endef

define Package/luci-app-jdc-tgbot/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-jdc-tgbot))
