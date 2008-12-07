#ifndef	_JFFS2_H_
#define _JFFS2_H_

/*
 * Stuffs grabbed from fs/jffs2/
 */

struct jffs2_raw_node_ref
{
	struct jffs2_raw_node_ref *next_in_ino; 
	struct jffs2_raw_node_ref *next_phys;
	uint32_t flash_offset;
	uint32_t totlen;	
};

struct jffs2_full_dirent
{
	struct jffs2_raw_node_ref *raw;
	struct jffs2_full_dirent *next;
	uint32_t version;
	uint32_t ino; /* == zero for unlink */
	unsigned int nhash;
	unsigned char type;
	unsigned char name[0];
};

struct jffs2_inode_cache {
	struct jffs2_full_dirent *scan_dents; 
	struct jffs2_inode_cache *next;
	struct jffs2_raw_node_ref *nodes;	
	uint32_t ino;
	int nlink;	
	int state;
};

#define INOCACHE_HASHSIZE 128
#define ref_flags(ref) ((ref)->flash_offset & 3)
#define ref_offset(ref) ((ref)->flash_offset & ~3)

#endif /* _JFFS2_H_ */
