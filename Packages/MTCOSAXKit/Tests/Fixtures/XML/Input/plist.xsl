<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:template match="/"><plist version="1.0"><dict><xsl:for-each select="//book"><key><xsl:value-of select="@id"/></key><string><xsl:value-of select="title"/></string></xsl:for-each></dict></plist></xsl:template>
</xsl:stylesheet>
