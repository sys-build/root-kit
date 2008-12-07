/*
 * jffs2map2.c:	export all jffs2_raw_inode and jffs2_raw_dirent of a file
 *
 * shrek2@www.linuxforum.net, 2005-12
 */

#ifndef	_KERNEL_	/* We are part of the kernel, */
#define _KERNEL_
#endif
#ifndef MODULE		/* Not a permanet part, though */
#define MODULE
#endif	

#include <linux/module.h>	
#include <linux/kernel.h>	
#include <linux/init.h>		/* module_init/cleanup, __init */
#include <linux/proc_fs.h>	/* procfs */
#include <linux/spinlock.h>	/* spinlock_t */
#include <linux/fs.h>		/* VFS data struct and 
				   extern struct list_head super_blocks;
				   extern spinlock_t sb_lock;	
				*/
#include <linux/jffs2_fs_sb.h>	/* jffs2_sb_info */
#include <linux/jffs2.h>	/* JFFS2_SUPER_MAGIC 
				   struct jffs2_raw_inode, struct jffs2_raw_dirent
				*/
#include <linux/types.h>
#include <linux/list.h>		
#include <linux/errno.h>	
#include <linux/mtd/mtd.h>	/* jffs2_sb_info.mtd->read */
#include <linux/crc32.h>	/* crc32 */
#include <linux/slab.h>		/* kmalloc */
#include "jffs2.h"

#define JFFS2MAP_INO_DEFAULT	1
static int jffs2map_ino = 0;
MODULE_PARM(jffs2map_ino, "i");
MODULE_PARM_DESC(jffs2map_ino, "The file we are inspecting (default '/')");
#if 0
static char* jffs2map_devname = NULL;
MODULE_PARM(jffs2map_devname, "s");
MODULE_PARM_DESC(jffs2map_devname, "The device path where the FS we are inspecting is settled on, such as /dev/mtdblock/5");
#else

/* In my system, the root jffs2 is settled on /dev/mtdblock4,
 * of which the major is 31 and the minor is 4. Adjust according to your specification.
 */
#define JFFS2MAP_SDEV_DEFAULT 	((31 << 8) | 4)
#include <linux/kdev_t.h>	/* to_kdev_t */
static int jffs2map_sdev = 0;
MODULE_PARM(jffs2map_sdev, "i");
MODULE_PARM_DESC(jffs2map_sdev, "The dev_t of the device where the FS we are inspecting is settled on");
#endif
MODULE_AUTHOR("shrek2 at www.linuxforum.net");
MODULE_DESCRIPTION("To display the information of flash physical data of a file");

static unsigned char *jffs2map_nodestate[] = {"unchecked", "checking", "checkedabsent", "readinginode", "(padding)", "present"};
static unsigned char *jffs2map_noderef[] = {"unchecked", "obsolete", "pristine", "normal"};
static unsigned char *jffs2map_filetype[] = {"UNKNOWN", "FIFO", "CHR", "(invalid)", "DIR", "(invalid)", "BLK", "(invalid)", "REG", "(invalid)", "LNK", "(invalid)", "SOCK", "(invalid)", "WHT"};

/* Read each node on flash indicated by the list of f->nodes
 * Hold jffs2_sb_info.erase_completion_lock during accessing jffs2_inode_cache.nodes
 */
static void 
jffs2map_display_info(char *buf, int *len_in, struct jffs2_sb_info *c, struct jffs2_inode_cache *f)
{
	union jffs2_node_union nodeunion;
	struct jffs2_raw_node_ref *node = NULL;
	int err, retlen, len = *len_in;
	uint32_t crc;
	uint16_t rdev;
	
	/* Directory has ONLY one jffs2_raw_inode, whereas others can have
	 * more. We fetch jffs2_raw_inode.mode only once. */
	static int file_type_displayed = 0;

	if (f->nodes == NULL)
		return;

	spin_lock_bh(&c->erase_completion_lock);
	/* We want to display EVERY nodes on the list, no matter being normal or obsolete. */		
	for (node = f->nodes; (unsigned char *)node != (unsigned char *)f; 
			node = node->next_in_ino){
		
		len += sprintf(buf+len, "<%s,0x%x,0x%x>,",
					jffs2map_noderef[ref_flags(node)],
					ref_offset(node), node->totlen);
							
		/* Grabbed from fs/jffs2/nodelist.c, i LOVE open source ;-)*/
		err = c->mtd->read(c->mtd, (ref_offset(node)), 
					min(node->totlen, sizeof(nodeunion)),
					&retlen, (void *)&nodeunion);
		if (err) {
			printk(KERN_INFO "error %d reading node at 0x%x\n", err, ref_offset(node));
			goto out_display;
		}							
			
		/* Check we've managed to read at least the common node header */
		if (retlen < min(node->totlen, sizeof(nodeunion.u))) {
			printk(KERN_INFO "short read in get_inode_nodes\n");
			goto out_display;
		}
		
 		/* Check crc */
		crc = crc32(0, &nodeunion, sizeof(nodeunion.u)-4);
		if (crc != je32_to_cpu(nodeunion.u.hdr_crc)){
			len += sprintf(buf+len, "Header CRC %x != calculated CRC %x for node at %x\n",
		       			je32_to_cpu(nodeunion.u.hdr_crc), crc, ref_offset(node));
		       	/* goto out_display; */ /* Ignore error */
		}
			
		switch (je16_to_cpu(nodeunion.u.nodetype)) {
		case JFFS2_NODETYPE_DIRENT:
			/* Check crc */
			crc = crc32(0, &nodeunion, sizeof(nodeunion.d)-8);
			if (crc != je32_to_cpu(nodeunion.d.node_crc)){
				len += sprintf(buf+len, "Jffs2_raw_dirent CRC %x != calculated CRC %x for node at %x\n",
		       			je32_to_cpu(nodeunion.d.node_crc), crc, ref_offset(node));
		       		/* goto out_display; */ /* Ignore error */	
			}
			
			len += sprintf(buf+len, "jffs2_raw_dirent,ino=%d,pino=%d,type=%s,name: ",
						je32_to_cpu(nodeunion.d.ino), 
						je32_to_cpu(nodeunion.d.pino), 
						jffs2map_filetype[nodeunion.d.type & DT_WHT]);
		
			/* memcpy as much of the name as possible from the raw
			   dirent we've already read from the flash */
			if (retlen > sizeof(struct jffs2_raw_dirent)){
				int length = min((uint32_t)nodeunion.d.nsize,
						 (retlen - sizeof(struct jffs2_raw_dirent)));
				memcpy(buf+len, &nodeunion.d.name[0], length);
				len += length; 
			}
			/* Do we need to copy any more of the name directly from the flash? */
			/* Bypass checking name_crc, lazy me */
			if (nodeunion.d.nsize + sizeof(struct jffs2_raw_dirent) > retlen) {
				int already = retlen - sizeof(struct jffs2_raw_dirent);					
				err = c->mtd->read(c->mtd, (ref_offset(node))+retlen,
							   nodeunion.d.nsize-already, 
							   &retlen, (void *)(buf+len));
				if (err) {
					printk(KERN_INFO "Read remainder of name error %d\n", err);
					goto out_display;
				}
				len += retlen;
			}
			len += sprintf(buf+len, "\n");
			break;			
		case JFFS2_NODETYPE_INODE:
			/* Check crc */
			crc = crc32(0, &nodeunion, sizeof(nodeunion.i)-8);
			if (crc != je32_to_cpu(nodeunion.i.node_crc)){
				len += sprintf(buf+len, "Jffs2_raw_inode NODE CRC %x != calculated CRC %x for node at %x\n",
		       			je32_to_cpu(nodeunion.i.node_crc), crc, ref_offset(node));
		       		/* goto out_display; */ /* Ignore error */	
			}

			len += sprintf(buf+len, "jffs2_raw_inode,ino=%d,dsize=0x%x,csize=0x%x\n",
						je32_to_cpu(nodeunion.i.ino),
						je32_to_cpu(nodeunion.i.dsize),
						je32_to_cpu(nodeunion.i.csize));

			if (!file_type_displayed){
				switch(je32_to_cpu(nodeunion.i.mode) & S_IFMT){				
				case S_IFREG:
					len += sprintf(buf+len, "A regular file.");
				break;
				case S_IFDIR:
					len += sprintf(buf+len, "A directory.");
					/* TODO:
					 * #include <linux/dcache.h>	// d_mountpoint 
					 * Check whether it is a mountpoint,
					 * if yes, print vfsmount.mnt_devname
					 *
					 * Note:
					 * 1, my current Linux version is too old to have d_vfsmnt in dentry!
					 * 2, we only have the ino of the directory, try to find its dentry first.
					 */
				break;
				case S_IFIFO:
					len += sprintf(buf+len, "A pipe.");
				break;
				case S_IFSOCK:
					len += sprintf(buf+len, "A socket.");
				break;
				case S_IFCHR:
					len += sprintf(buf+len, "A char device, ");
					if (nodeunion.i.compr == JFFS2_COMPR_NONE){
						len += sprintf(buf+len, "rdev=");
						err = c->mtd->read(c->mtd, (ref_offset(node))+sizeof(nodeunion.i), 
									sizeof(rdev), &retlen, (void *)&rdev);
						if (err){
							printk(KERN_INFO "Read char rdev error %d\n", err);
							goto out_display;
						}else
							len += sprintf(buf+len, "(0x%x, 0x%x)", 
									(rdev & 0xff00)>>8, (rdev & 0xff));
					}else
						len += sprintf(buf+len, "the rdev of the device is compressed.");	
				break;
				case S_IFBLK:
					len += sprintf(buf+len, "A block device, ");
					if (nodeunion.i.compr == JFFS2_COMPR_NONE){
						len += sprintf(buf+len, "rdev=");
						err = c->mtd->read(c->mtd, (ref_offset(node))+sizeof(nodeunion.i), 
									sizeof(rdev), &retlen, (void *)(buf+len));
						if (err){
							printk(KERN_INFO "Read block rdev error %d\n", err);
							goto out_display;
						}else
							len += sprintf(buf+len, "(0x%x, 0x%x)", 
									(rdev & 0xff00)>>8, (rdev & 0xff));
					}else
						len += sprintf(buf+len, "the rdev of the device is compressed.");
				break;
				case S_IFLNK:
					len += sprintf(buf+len, "A symbolic link, ");
					if (nodeunion.i.compr == JFFS2_COMPR_NONE){
						len += sprintf(buf+len, "the linked file is ");
						err = c->mtd->read(c->mtd, (ref_offset(node))+sizeof(nodeunion.i), 
									je32_to_cpu(nodeunion.i.dsize), &retlen, (void *)(buf+len));
						if (err || retlen!= je32_to_cpu(nodeunion.i.dsize)){
							printk(KERN_INFO "Read name of linked file error %d\n", err);
							goto out_display;
						}else	
							len += retlen;
					}else
						len += sprintf(buf+len, "the name of the linked file is compressed.");					
				break;				
				default:
					len += sprintf(buf+len, "Unknown file type");
				break;
				}// switch	
				len += sprintf(buf+len, "\n");		
				file_type_displayed++;
			}
			break;
		case JFFS2_NODETYPE_CLEANMARKER:		
			len += sprintf(buf+len, "A cleanmarker.\n");
			break;
		case JFFS2_NODETYPE_PADDING:
			len += sprintf(buf+len, "Padding.\n");
			break;
		default:
			len += sprintf(buf+len, "Unknown node type\n");
			break;
		}					
	}// for

out_display:
	/* spin_lock_bh disables bh, if spin_unlock_bh is placed inside this function rather than at the end, 
	 * kernel panic to kill interrupt handler will take place, which means there is a race condition between
	 * jffs2map_display_info and some bh.
  	 * next step: hunt down the bh. shrek2, 2005/11/24
	 */
	spin_unlock_bh(&c->erase_completion_lock);
	*len_in = len;
}

/* This is a bogus implemention, because if there are more than one jffs2 mounted,
 * it will always find the first jffs2's(the root jffs2's) super_block from super_blocks.
 *
static inline int
jffs2map_sbfound(struct super_block *s)
{
	return (s->s_magic == JFFS2_SUPER_MAGIC);	
}
*/

#if 0 	
/* In my current Linux version, there is NO s_mounts but s_instances in super_block,
 * and s_instances is used to link all sb of the same type in the list of file_system_type.fs_supers.
 * So I can't access vfsmount.mnt_devname through super_block,
 * and I have to use sb.s_dev and change to use jffs2map_sdev
 */
 	
/* Find FS that is actually settled on the device specified by jffs2map_devname
 * return 1 for success, 0 otherwise.
 */
static inline int
jffs2map_sbfound(struct super_block *s)
{
	struct list_head *p = s->s_mounts.next;
	struct vfsmount *mnt;
	
	/* FIXME: need to make sure wether the list of s_mounts is recycled or not*/
	while (p != &s->s_mounts){
		mnt = list_entry(p, struct vfsmount, mnt_instances);
		if (strcmp(mnt->devname, jffs2map_devname) == 0 &&
			s->s_magic == JFFS2_SUPER_MAGIC)
			return 1;
		else
			p = mnt->mnt_instances.next;			
	}
	
	return 0;		
}

#else

/* Find FS which s_dev equals to jffs2map_sdev
 */
static inline int
jffs2map_sbfound(struct super_block *s)
{
	return ((s->s_dev == to_kdev_t(jffs2map_sdev)) &&
		(s->s_magic == JFFS2_SUPER_MAGIC));	
}
#endif


/*
 * 1, Hold sb_lock and disable interrupt during accessing super_blocks,
 * 2, Hold jffs2_sb_info.alloc_sem during accessing jffs2_sb_info.inocache_list to block GC
 */
static int
jffs2map_read_proc(char *buf, char **start, off_t offset,
                   int count, int *eof, void *data)
{
	unsigned long flags;
	int len = 0, i = 0, ino, founded = 0;
	struct super_block *s = NULL;
	struct jffs2_sb_info *c = NULL;
	struct jffs2_inode_cache *f = NULL;
	struct jffs2_inode_cache **head = NULL;
	
	if (!jffs2map_sdev){
		jffs2map_sdev = JFFS2MAP_SDEV_DEFAULT;
	}
	len += sprintf(buf+len, "Display jffs2 with s_dev = (%u,%u).\n", MAJOR(jffs2map_sdev), MINOR(jffs2map_sdev));
	
	/* Fetch super_block of jffs2 */
	spin_lock_irqsave(&sb_lock, flags);
	s = sb_entry(super_blocks.next);
	while (s != sb_entry(&super_blocks)){
		if (jffs2map_sbfound(s))
			break;
		else
			s = sb_entry(s->s_list.next);
	}
	spin_unlock_irqrestore(&sb_lock, flags);
	if (s == sb_entry(&super_blocks)){
		printk(KERN_INFO "No super_block found! Pls make sure jffs2map_sdev is valid!\n");
		return -ENOENT;
	}

	c = &s->u.jffs2_sb;
	if (down_interruptible(&c->alloc_sem))
		return -ERESTARTSYS;
	
	len += sprintf(buf+len, "The highest ino is %d, ", c->highest_ino);

	/* Get the file to play with */
	ino = jffs2map_ino ? jffs2map_ino : JFFS2MAP_INO_DEFAULT;
	if (ino > c->highest_ino){
		len += sprintf(buf+len, "\nPlease speccify a ino less than %d", c->highest_ino);
		goto out_read_proc;
	}else
		len += sprintf(buf+len, "displaying file information with ino %d\n", ino);
	
	head = c->inocache_list;
	i = 0;
	do {
		if (*head){
			for (f = *head; f; f = f->next){
				if (f->ino == ino){
					len += sprintf(buf+len, "ino=%d, nlink=0x%x, state: %s\n",			
							 f->ino, f->nlink, jffs2map_nodestate[f->state]);
					jffs2map_display_info(buf, &len, c, f);
					founded++;
					break;
				}		
			}					
		}
		head++;
		i++;	
	}while (!founded && i<INOCACHE_HASHSIZE);		

out_read_proc:	
	up(&c->alloc_sem);
	*eof = 1;
    	return len;
}

static void jffs2map_create_proc()
{
    	create_proc_read_entry("jffs2map", 
    			   	0, /* default mode */
                           	NULL, /* parent dir */
                           	jffs2map_read_proc,
                           	NULL); /* client data */                       	
}

static void jffs2map_remove_proc()
{
       	remove_proc_entry("jffs2map", 
       			  NULL); /* parent dir */
}

static int jffs2map_init(void)
{
	jffs2map_create_proc();
	return 0;
}

static void jffs2map_cleanup(void)
{
	jffs2map_remove_proc();	
}

module_init(jffs2map_init);
module_exit(jffs2map_cleanup);
