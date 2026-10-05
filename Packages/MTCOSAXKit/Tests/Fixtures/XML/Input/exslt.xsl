<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:str="http://exslt.org/strings" extension-element-prefixes="str">
	<xsl:output method="text"/>
	<xsl:template match="/"><xsl:for-each select="str:tokenize('a,b,c', ',')"><xsl:value-of select="."/>|</xsl:for-each></xsl:template>
</xsl:stylesheet>
