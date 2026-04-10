include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-tgpasswall
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-tgpasswall
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI app for Telegram + Passwall controller
  DEPENDS:=+curl +coreutils +coreutils-base64 +jq +luci-base +luci-compat +jsonfilter
endef

define Package/luci-app-tgpasswall/description
 Telegram Bot control bridge for OpenWrt system status and luci-app-passwall operations.
endef

define Build/Compile
endef

define Package/luci-app-tgpasswall/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-tgpasswall))
