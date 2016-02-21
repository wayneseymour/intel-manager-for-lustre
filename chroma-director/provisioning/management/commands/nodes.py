from provisioning.lib.image_ops import ImageOps
from provisioning.models import ChromaManager, ChromaAppliance, Node

import settings
from django.core.management.base import BaseCommand
from provisioning.lib.chroma_ops import NodeOps

class Command(BaseCommand):
    args = "list|ssh <id>|terminate all|terminate <id>|new_image <id> <name>"
    help = "Utility command to manage instances"
    can_import_settings = True

    def handle(self, *args, **options):
        if not args or args[0] == 'list':
            for n in Node.objects.all():
                i = n.get_instance()
                if i:
                    print n.id, n.ec2_id, n.name, i.instance_type, i.launch_time, i.state, i.ip_address
                else:
                    print n.id, n.ec2_id, n.name, "No EC2 instance found"

        elif args[0] == 'terminate' and args[1] == 'all':
            for node in Node.objects.all():
                node_ops = NodeOps(node)
                node_ops.terminate()

        elif args[0] == 'terminate' and int(args[1]) > 0:
            node_id = int(args[1])
            node_ops = NodeOps.get(node_id)
            node_ops.terminate()

        elif args[0] == 'new_image':
            node_id = int(args[1])
            image_name = args[2]
            node = Node.objects.get(id = node_id)
            image_ops = ImageOps(node)
            image_ops.make_image(image_name)

        elif args[0] == 'ssh':
            node_id = int(args[1])
            node = Node.objects.get(id = node_id)
            session = node.get_session()
            import os
            SSH_BIN = "/usr/bin/ssh"
            os.execvp(SSH_BIN, ["ssh", "-i", settings.AWS_SSH_PRIVATE_KEY, 
                                "%s@%s" % (node.username, session.instance.ip_address)])
        else:
            print "unknown command %s" % args[0]



