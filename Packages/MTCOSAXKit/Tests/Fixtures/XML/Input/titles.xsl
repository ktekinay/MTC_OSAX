<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:param name="label" select="'Titles'"/>
	<xsl:output method="xml" indent="yes"/>
	<xsl:template match="/">
		<titles label="{$label}">
			<xsl:for-each select="//book">
				<title id="{@id}"><xsl:value-of select="title"/></title>
			</xsl:for-each>
		</titles>
	</xsl:template>
</xsl:stylesheet>
